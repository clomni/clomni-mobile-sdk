package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import kotlin.math.abs

/**
 * Entry point of the protocol layer (`protocol/schema`): parses what the server sends, encodes what the client sends.
 *
 * Parsing never throws, and follows the same rules as the iOS SDK:
 * - unknown fields are skipped; JSON `null` reads as absent;
 * - a message whose envelope is unusable (a required field missing or of the wrong JSON type) is null;
 * - an unknown type, broken content of a known type, or an empty buttons/fields/cards list (it would leave the user
 *   stuck) gives [MessageContent.Unknown], shown with `fallback_text`;
 * - an unknown event, or a known one with broken data, gives [RealtimeEvent.Payload.Unknown];
 * - lengths and patterns are not checked (`lang: "de"`, a 181-character push body): the value is kept.
 *
 * Whatever is dropped or downgraded is reported to [logger], meant for the debug log.
 */
internal class ProtocolJson(private val logger: (String) -> Unit = {}) {

    /** A message as REST or the socket sends it; null when its envelope is unusable. */
    fun parseMessage(json: String): Message? = guard("message") { message(json.toJsonObject()) }

    /** The same, for a message inside a larger body that was already parsed (a page of messages). */
    fun parseMessage(element: JsonElement): Message? = guard("message") { message(element.asObject("message")) }

    /** A text WebSocket frame; null only when it is not JSON or has no event name. */
    fun parseEvent(json: String): RealtimeEvent? = guard("event") { event(json.toJsonObject()) }

    /** Null only when the body is not a JSON object; every missing or broken field takes its default. */
    fun parseConfig(json: String): MessengerConfig? = guard("config") { config(json.toJsonObject()) }

    /**
     * GET /news. An item without an id or a title is left out; a title over 80 characters is cut there, and a button
     * without a text or an address is left off, each logged (protocol fixtures 63, 64).
     */
    fun parseNews(json: String): List<NewsItem>? = guard("news") {
        (json.toJsonObject()["items"] as? JsonArray).orEmpty().mapNotNull { element ->
            val o = element as? JsonObject ?: return@mapNotNull null
            val id = o.string("id") ?: return@mapNotNull null.also { logger("news item without an id dropped") }
            val title = o.string("title")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null.also { logger("news $id without a title dropped") }
            val button = (o["button"] as? JsonObject)?.let { b ->
                val text = b.string("text")
                val url = b.string("url")
                if (text.isNullOrBlank() || url.isNullOrBlank()) null.also { logger("news $id: button without text or url left off") } else NewsItem.Button(text, url)
            }
            NewsItem(
                id = id,
                title = if (title.length > 80) title.take(80).also { logger("news $id: title over 80 characters cut") } else title,
                summary = o.string("summary"),
                bodyMarkdown = o.string("body_markdown"),
                imageUrl = o.string("image_url"),
                button = button,
                publishedAt = o.string("published_at")?.let(Iso8601::parseMillis),
            )
        }
    }

    /** Null when the payload is not a Clomni push (`"clomni": "1"`) or lacks a required key. */
    fun parsePush(json: String): PushPayload? = guard("push") { push(json.toJsonObject()) }

    /** An FCM data message (`RemoteMessage.data`), where every value is a string. */
    fun parsePush(data: Map<String, String>): PushPayload? =
        guard("push") { push(JsonObject(data.mapValues { JsonPrimitive(it.value) })) }

    /** A client message read back, e.g. one the outbox kept on disk. */
    fun parseClientMessage(json: String): ClientMessage? =
        guard("client message") { clientMessage(json.toJsonObject()) }

    /** POST /mobile/sessions and /mobile/sessions/refresh. */
    fun parseSession(json: String): MobileSession? = guard("session") { session(json.toJsonObject()) }

    fun parseConversation(json: String): Conversation? =
        guard("conversation") { conversation(json.toJsonObject()) }

    /** GET /conversations. */
    fun parseConversationPage(json: String): ConversationPage? = guard("conversations") {
        val o = json.toJsonObject()
        ConversationPage(o.items("conversations", ::conversation), o.string("next_cursor"))
    }

    /** GET /conversations/{id}/messages. */
    fun parseMessagePage(json: String): MessagePage? = guard("messages") {
        val o = json.toJsonObject()
        MessagePage(o.items("messages", ::message), o.boolean("has_more") ?: false)
    }

    /** POST /conversations. */
    fun parseConversationWithMessages(json: String): ConversationWithMessages? =
        guard("conversation") { conversationWithMessages(json.toJsonObject()) }

    /** POST /flows/trigger. */
    fun parseFlowTrigger(json: String): FlowTriggerResult? = guard("flow trigger") {
        val o = json.toJsonObject()
        FlowTriggerResult(
            started = o.boolean("started") ?: throw ProtocolException("started: expected a boolean"),
            conversation = (o["conversation"] as? JsonObject)?.let(::conversationWithMessages),
        )
    }

    fun parseUser(json: String): MobileUser? = guard("user") {
        val o = json.toJsonObject()
        MobileUser(
            id = o.requireString("id"),
            anonymous = o.boolean("anonymous") ?: throw ProtocolException("anonymous: expected a boolean"),
            name = o.string("name"),
            email = o.string("email"),
            phone = o.string("phone"),
            language = o.string("language"),
            customAttributes = o["custom_attributes"] as? JsonObject ?: emptyMap(),
        )
    }

    fun parseUpload(json: String): UploadedFile? = guard("upload") {
        val o = json.toJsonObject()
        UploadedFile(
            uploadId = o.requireString("upload_id"),
            url = o.requireString("url"),
            name = o.requireString("name"),
            size = o.long("size") ?: throw ProtocolException("size: expected an integer"),
            mime = o.requireString("mime"),
        )
    }

    /** Null for a body that is not an `Error` (a proxy's HTML page, say); the status then says what happened. */
    fun parseServerError(json: String): ServerError? = try {
        val error = json.toJsonObject().requireObject("error")
        ServerError(
            code = error.requireString("code"),
            message = error.string("message").orEmpty(),
            requestId = error.string("request_id"),
            fields = error.section("fields").let { fields ->
                fields.keys.mapNotNull { key -> fields.string(key)?.let { key to it } }.toMap()
            },
        )
    } catch (e: Exception) {
        null
    }

    /** The request body for POST /v1/conversations/{id}/messages. */
    fun encode(message: ClientMessage): String = buildJsonObject {
        put("client_id", message.clientId)
        put("type", message.type)
        putJsonObject("content") {
            when (message) {
                is ClientMessage.Text -> put("text", message.text)
                is ClientMessage.ButtonReply -> {
                    put("reply_to", message.replyTo)
                    put("button_id", message.buttonId)
                    put("payload", message.payload)
                }
                is ClientMessage.FormSubmit -> {
                    put("reply_to", message.replyTo)
                    put("form_id", message.formId)
                    put("values", JsonObject(message.values))
                }
                is ClientMessage.Attachment -> {
                    put("upload_id", message.uploadId)
                    put("caption", message.caption)
                }
                is ClientMessage.RatingSubmit -> {
                    put("reply_to", message.replyTo)
                    put("score", message.score)
                    put("comment", message.comment)
                }
            }
        }
    }.toString()

    /** [content] read as the content of a message of [type]: a known content, or [MessageContent.Unknown]. */
    fun parseContent(type: String, content: JsonElement): MessageContent = content(type, content, null)

    private inline fun <T : Any> guard(what: String, parse: () -> T?): T? = try {
        parse()
    } catch (e: Exception) {
        logger("${e.message}; $what dropped")
        null
    }

    // Messages

    private fun message(o: JsonObject): Message {
        val id = o.requireString("id")
        val type = o.requireString("type")
        val content = o["content"] as? JsonObject ?: throw ProtocolException("content: expected an object")
        val conversationId = o.requireString("conversation_id")
        val sender = sender(o.requireObject("sender"))
        val createdAt = o.requireTime("created_at")
        val seq = o.long("seq") ?: throw ProtocolException("seq: expected an integer")
        val lang = o.requireString("lang")
        val fallbackText = o.requireString("fallback_text")
        val flow = o.present("flow")?.let {
            try {
                flow(it.asObject("flow"))
            } catch (e: ProtocolException) {
                logger("$id: ${e.message}; shown without its flow")
                null
            }
        }
        // Content last, so a message dropped for its envelope does not also log about its content.
        return Message(
            id = id,
            clientId = o.string("client_id"),
            conversationId = conversationId,
            type = type,
            sender = sender,
            createdAt = createdAt,
            seq = seq,
            lang = lang,
            flow = flow,
            content = content(type, content, id),
            fallbackText = fallbackText,
        )
    }

    private fun sender(o: JsonObject) =
        Sender(SenderType.from(o.requireString("type")), o.string("id"), o.string("name"), o.string("avatar_url"))

    private fun flow(o: JsonObject) = FlowRef(
        flowId = o.requireString("flow_id"),
        nodeId = o.requireString("node_id"),
        version = o.int("version"),
        interactive = o.boolean("interactive") ?: throw ProtocolException("interactive: expected a boolean"),
    )

    private fun content(type: String, content: JsonElement, messageId: String?): MessageContent {
        val prefix = messageId?.let { "$it: " }.orEmpty()
        val parse: ((JsonObject) -> MessageContent)? = when (type) {
            "text" -> { o -> MessageContent.Text(o.requireString("text")) }
            "quick_replies" -> ::quickReplies
            "image" -> ::image
            "file" -> ::file
            "form" -> ::form
            "system" -> ::system
            "card" -> { o -> MessageContent.Card(o.nonEmptyArray("cards").map { cardItem(it.asObject("card")) }) }
            "rating" -> ::rating
            else -> null
        }
        if (parse == null) {
            logger("${prefix}unknown type \"$type\", shown as fallback_text")
            return MessageContent.Unknown(type, content)
        }
        if (content !is JsonObject) {
            logger("$prefix$type: expected an object; shown as fallback_text")
            return MessageContent.Unknown(type, content)
        }
        return try {
            parse(content)
        } catch (e: ProtocolException) {
            logger("$prefix$type.${e.message}; shown as fallback_text")
            MessageContent.Unknown(type, content)
        }
    }

    private fun quickReplies(o: JsonObject) = MessageContent.QuickReplies(
        text = o.string("text"),
        buttons = o.nonEmptyArray("buttons").map {
            val button = it.asObject("button")
            MessageContent.Button(
                id = button.requireString("id"),
                title = button.requireString("title"),
                icon = button.string("icon"),
                payload = button.requireString("payload"),
            )
        },
        layout = if (o.string("layout") == "chips") {
            MessageContent.QuickRepliesLayout.CHIPS
        } else {
            MessageContent.QuickRepliesLayout.VERTICAL
        },
        inputDisabled = o.boolean("input_disabled") ?: false,
        allowBack = o.boolean("allow_back") ?: false,
    )

    private fun image(o: JsonObject) = MessageContent.Image(
        url = o.requireString("url"),
        thumbUrl = o.string("thumb_url"),
        // A zero size would divide by zero when the UI reserves the aspect ratio.
        width = o.int("width")?.takeIf { it > 0 },
        height = o.int("height")?.takeIf { it > 0 },
        caption = o.string("caption"),
    )

    private fun file(o: JsonObject) = MessageContent.File(
        url = o.requireString("url"),
        name = o.requireString("name"),
        size = o.long("size") ?: throw ProtocolException("size: expected an integer"),
        mime = o.requireString("mime"),
    )

    private fun form(o: JsonObject) = MessageContent.Form(
        text = o.string("text"),
        formId = o.requireString("form_id"),
        fields = o.nonEmptyArray("fields").map { formField(it.asObject("field")) },
        submitTitle = o.requireString("submit_title"),
        submitted = o["submitted"] as? JsonObject,
    )

    private fun formField(o: JsonObject): MessageContent.FormField {
        val type = MessageContent.FormFieldType.from(o.requireString("type"))
        return MessageContent.FormField(
            key = o.requireString("key"),
            type = type,
            label = o.requireString("label"),
            required = o.boolean("required") ?: false,
            maxLength = o.int("max_length"),
            defaultCountry = o.string("default_country"),
            placeholder = o.string("placeholder"),
            options = if (type == MessageContent.FormFieldType.SELECT) {
                o.requireArray("options").map {
                    val option = it.asObject("option")
                    MessageContent.FormField.Option(option.requireString("value"), option.requireString("label"))
                }
            } else {
                emptyList()
            },
        )
    }

    private fun system(o: JsonObject) = MessageContent.System(
        event = when (val event = o.requireString("event")) {
            "operator_joined" -> MessageContent.SystemEvent.OperatorJoined
            "assigned_to_team" -> MessageContent.SystemEvent.AssignedToTeam
            "conversation_closed" -> MessageContent.SystemEvent.ConversationClosed
            "conversation_reopened" -> MessageContent.SystemEvent.ConversationReopened
            "waiting_in_queue" -> MessageContent.SystemEvent.WaitingInQueue
            else -> MessageContent.SystemEvent.Unknown(event)
        },
        text = o.requireString("text"),
        position = o.int("position"),
    )

    private fun cardItem(o: JsonObject) = MessageContent.CardItem(
        imageUrl = o.string("image_url"),
        title = o.requireString("title"),
        subtitle = o.string("subtitle"),
        buttons = if (o.present("buttons") != null) {
            o.requireArray("buttons").map { cardButton(it.asObject("card button")) }
        } else {
            emptyList()
        },
    )

    private fun cardButton(o: JsonObject): MessageContent.CardButton {
        val payload = o.string("payload")
        val url = o.string("url")
        if (payload == null && url == null) throw ProtocolException("card button: expected a payload or a url")
        return MessageContent.CardButton(o.requireString("id"), o.requireString("title"), payload, url)
    }

    private fun rating(o: JsonObject): MessageContent.Rating {
        val text = o.requireString("text")
        val scale = o.requireString("scale")
        return MessageContent.Rating(
            text = text,
            scale = MessageContent.RatingScale.from(scale)
                ?: throw ProtocolException("scale: unknown scale \"$scale\""),
            comment = MessageContent.RatingComment.from(o.string("comment")),
            submitted = o["submitted"] as? JsonObject,
        )
    }

    // Realtime events

    private fun event(o: JsonObject): RealtimeEvent {
        val name = o.requireString("event")
        val payload = try {
            payload(name, o["data"])
        } catch (e: ProtocolException) {
            logger("$name: ${e.message}; event ignored")
            RealtimeEvent.Payload.Unknown(name)
        }
        return RealtimeEvent(name, payload, o.string("ts")?.let(Iso8601::parseMillis))
    }

    private fun payload(name: String, data: JsonElement?): RealtimeEvent.Payload {
        val d by lazy { data.asObject("data") }
        return when (name) {
            "ready" -> RealtimeEvent.Payload.Ready(
                userId = d.requireString("user_id"),
                heartbeatSec = d.int("heartbeat_sec") ?: throw ProtocolException("heartbeat_sec: expected an integer"),
            )
            "message.created" -> RealtimeEvent.Payload.MessageCreated(message(d))
            "message.updated" -> RealtimeEvent.Payload.MessageUpdated(message(d))
            "typing" -> {
                val state = d.requireString("state")
                if (state != "on" && state != "off") throw ProtocolException("state: expected on or off")
                RealtimeEvent.Payload.Typing(
                    conversationId = d.requireString("conversation_id"),
                    sender = sender(d.requireObject("sender")),
                    isTyping = state == "on",
                )
            }
            "read" -> RealtimeEvent.Payload.Read(
                conversationId = d.requireString("conversation_id"),
                upToSeq = d.long("up_to_seq") ?: throw ProtocolException("up_to_seq: expected an integer"),
                by = SenderType.from(d.requireString("by")),
            )
            "conversation.updated" -> RealtimeEvent.Payload.ConversationUpdated(
                RealtimeEvent.ConversationUpdate(
                    id = d.requireString("id"),
                    status = ConversationStatus.from(d.requireString("status")),
                    assignee = (d["assignee"] as? JsonObject)?.let(::assignee),
                    unreadCount = d.int("unread_count"),
                ),
            )
            "unread.changed" -> RealtimeEvent.Payload.UnreadChanged(
                d.int("total") ?: throw ProtocolException("total: expected an integer"),
            )
            "config.changed" -> RealtimeEvent.Payload.ConfigChanged(d.requireString("etag"))
            "ping" -> RealtimeEvent.Payload.Ping
            else -> {
                logger("unknown event \"$name\" ignored")
                RealtimeEvent.Payload.Unknown(name)
            }
        }
    }

    private fun assignee(o: JsonObject) = Assignee(o.requireString("name"), o.string("avatar_url"), o.boolean("online"))

    // Mobile API bodies

    private fun session(o: JsonObject): MobileSession {
        val user = o.requireObject("user")
        return MobileSession(
            sessionToken = o.requireString("session_token"),
            expiresAt = o.requireTime("expires_at"),
            refreshToken = o.requireString("refresh_token"),
            userId = user.requireString("id"),
            anonymous = user.boolean("anonymous") ?: throw ProtocolException("anonymous: expected a boolean"),
            language = user.string("language"),
            wsUrl = o.requireString("ws_url"),
        )
    }

    private fun conversation(o: JsonObject) = Conversation(
        id = o.requireString("id"),
        status = ConversationStatus.from(o.requireString("status")),
        assignee = (o["assignee"] as? JsonObject)?.let(::assignee),
        unreadCount = o.int("unread_count") ?: 0,
        lastMessage = (o["last_message"] as? JsonObject)?.let(::message),
        flow = (o["flow"] as? JsonObject)?.let { flow ->
            val flowId = flow.string("flow_id")
            val nodeId = flow.string("node_id")
            if (flowId != null && nodeId != null) Conversation.FlowStep(flowId, nodeId) else null
        },
        openedFrom = o.string("opened_from"),
        createdAt = o.requireTime("created_at"),
    )

    private fun conversationWithMessages(o: JsonObject) =
        ConversationWithMessages(conversation(o.requireObject("conversation")), o.items("messages", ::message))

    /** A required array whose unreadable items are dropped with a log line. */
    private fun <T> JsonObject.items(key: String, read: (JsonObject) -> T): List<T> =
        requireArray(key).mapIndexedNotNull { index, element ->
            try {
                read(element.asObject("$key[$index]"))
            } catch (e: ProtocolException) {
                logger("$key[$index]: ${e.message}; item dropped")
                null
            }
        }

    // Config, push and client messages

    private fun config(o: JsonObject): MessengerConfig {
        val brand = o.section("brand")
        val home = o.section("home")
        val team = o.section("team")
        val bot = o.section("bot")
        val theme = o.section("theme")
        val launcher = theme.section("launcher")
        val composer = o.section("composer")
        val limits = o.section("limits")
        val primaryColor = brand.string("primary_color")
        return MessengerConfig(
            version = o.int("version") ?: 0,
            brand = MessengerConfig.Brand(
                name = brand.string("name") ?: "",
                logoUrl = brand.string("logo_url"),
                logoDarkUrl = brand.string("logo_dark_url"),
                primaryColor = primaryColor?.takeIf { hexColor.matches(it) } ?: run {
                    logger("brand.primary_color \"$primaryColor\" is not #RRGGBB; default colour used")
                    MessengerConfig.Brand.DEFAULT_PRIMARY_COLOR
                },
                headerStyle = when (brand.string("header_style")) {
                    "solid" -> MessengerConfig.HeaderStyle.SOLID
                    "image" -> MessengerConfig.HeaderStyle.IMAGE
                    else -> MessengerConfig.HeaderStyle.GRADIENT
                },
                headerImageUrl = brand.string("header_image_url"),
                wordmarkUrl = brand.string("wordmark_url").takeIf { brand.string("logo_style") == "wordmark" },
                logoScale = brand.int("logo_scale")?.coerceIn(60, 200) ?: 100,
                wordmarkDarkUrl = brand.string("wordmark_dark_url").takeIf { brand.string("logo_style") == "wordmark" },
                glow = brand.boolean("glow") ?: false,
                colors = colors(brand.section("colors")),
            ),
            team = MessengerConfig.Team(
                show = team.boolean("show") ?: true,
                avatars = (team["avatars"] as? JsonArray)?.strings().orEmpty(),
                replyTime = team.string("reply_time"),
                replyTimeOffline = team.string("reply_time_offline"),
                officeHours = (team["office_hours"] as? JsonObject)?.let {
                    MessengerConfig.OfficeHours(
                        it.string("tz"),
                        it.boolean("open_now") ?: true,
                        it.string("next_open_at")?.let(Iso8601::parseMillis),
                    )
                },
            ),
            bot = MessengerConfig.Bot(bot.string("name") ?: "", bot.string("avatar_url")),
            home = MessengerConfig.Home(
                cards = homeCards(home["cards"] as? JsonArray),
                channels = (home["channels"] as? JsonArray).orEmpty().mapNotNull { element ->
                    val channel = element as? JsonObject ?: return@mapNotNull null
                    val type = channel.string("type") ?: return@mapNotNull null
                    channel.string("url")?.let { MessengerConfig.Channel(type, it) }
                }.take(MessengerConfig.MAX_CHANNELS),
                // title_scale; a draft from before it has title_size, which the server maps the same way.
                titleScale = home.int("title_scale")?.coerceIn(70, 140) ?: when (home.string("title_size")) {
                    "s" -> 85
                    "l" -> 120
                    else -> 100
                },
            ),
            theme = MessengerConfig.ThemeSettings(
                mode = when (theme.string("mode")) {
                    "light" -> MessengerConfig.ThemeMode.LIGHT
                    "dark" -> MessengerConfig.ThemeMode.DARK
                    else -> MessengerConfig.ThemeMode.SYSTEM
                },
                launcher = MessengerConfig.Launcher(
                    enabled = launcher.boolean("enabled") ?: false,
                    position = if (launcher.string("position") == "left") {
                        MessengerConfig.LauncherPosition.LEFT
                    } else {
                        MessengerConfig.LauncherPosition.RIGHT
                    },
                    bottomPadding = launcher.int("bottom_padding")?.coerceIn(0, 200) ?: 20,
                ),
            ),
            composer = MessengerConfig.Composer(
                attachments = composer.boolean("attachments") ?: true,
                emoji = composer.boolean("emoji") ?: true,
            ),
            languages = (o["languages"] as? JsonArray)?.strings().orEmpty().ifEmpty { listOf("az") },
            strings = o.section("strings").let { strings ->
                strings.keys.mapNotNull { key -> strings.string(key)?.let { key to it } }.toMap()
            },
            limits = MessengerConfig.Limits(
                imageMb = limits.int("image_mb")?.takeIf { it > 0 } ?: 10,
                fileMb = limits.int("file_mb")?.takeIf { it > 0 } ?: 25,
                textChars = limits.int("text_chars")?.takeIf { it > 0 } ?: 4000,
            ),
            poweredBy = o.boolean("powered_by") ?: true,
            startsWithFlow = o.section("conversation").boolean("starts_with_flow") ?: false,
            sounds = o.boolean("sounds") ?: true,
        )
    }

    /** The panel's order of the known cards; "send" is always there, first unless placed. */
    private fun homeCards(cards: JsonArray?): List<MessengerConfig.HomeCard> {
        val known = cards?.strings()?.mapNotNull {
            when (it) {
                "messages" -> MessengerConfig.HomeCard.MESSAGES
                "news" -> MessengerConfig.HomeCard.NEWS
                "send" -> MessengerConfig.HomeCard.SEND
                "recent" -> MessengerConfig.HomeCard.RECENT
                "channels" -> MessengerConfig.HomeCard.CHANNELS
                else -> null
            }
        }?.distinct() ?: return MessengerConfig.HomeCard.entries
        // The list can be reached only from its card, and a conversation started only from send: both always there.
        val withSend = if (MessengerConfig.HomeCard.SEND in known) known else listOf(MessengerConfig.HomeCard.SEND) + known
        return if (MessengerConfig.HomeCard.MESSAGES in withSend) withSend else listOf(MessengerConfig.HomeCard.MESSAGES) + withSend
    }

    /** Both palettes, every colour #RRGGBB; anything less and the SDK derives them itself. */
    private fun colors(o: JsonObject): MessengerConfig.Colors? {
        fun palette(p: JsonObject?): MessengerConfig.Palette? {
            p ?: return null
            fun color(key: String) = p.string(key)?.takeIf { hexColor.matches(it) }
            return MessengerConfig.Palette(
                primary = color("primary") ?: return null,
                onPrimary = color("on_primary") ?: return null,
                primarySoft = color("primary_soft") ?: return null,
                primaryLine = color("primary_line") ?: return null,
                headerFrom = color("header_from") ?: return null,
                headerTo = color("header_to") ?: return null,
                headerText = color("header_text"),
                primaryStrong = color("primary_strong"),
            )
        }
        if (o.isEmpty()) return null
        val light = palette(o["light"] as? JsonObject)
        val dark = palette(o["dark"] as? JsonObject)
        if (light == null || dark == null) {
            logger("brand.colors incomplete; the SDK derives the colours")
            return null
        }
        return MessengerConfig.Colors(light, dark)
    }

    private fun push(o: JsonObject): PushPayload {
        if (o.string("clomni") != "1") throw ProtocolException("not a Clomni push")
        return PushPayload(
            type = o.requireString("type"),
            conversationId = o.requireString("conversation_id"),
            messageId = o.string("message_id"),
            title = o.requireString("title"),
            body = o.requireString("body"),
            avatarUrl = o.string("avatar_url"),
            // A relay that only carries strings (FCM data) delivers the count as "3".
            unreadTotal = o.int("unread_total") ?: o.string("unread_total")?.toIntOrNull(),
        )
    }

    private fun clientMessage(o: JsonObject): ClientMessage {
        val type = o.requireString("type")
        val c = o.requireObject("content")
        val clientId = o.requireString("client_id")
        return when (type) {
            "text" -> ClientMessage.Text(c.requireString("text"), clientId)
            "button_reply" -> ClientMessage.ButtonReply(
                replyTo = c.requireString("reply_to"),
                buttonId = c.requireString("button_id"),
                payload = c.requireString("payload"),
                clientId = clientId,
            )
            "form_submit" -> ClientMessage.FormSubmit(
                replyTo = c.requireString("reply_to"),
                formId = c.requireString("form_id"),
                values = c.requireObject("values").toMap(),
                clientId = clientId,
            )
            "attachment" -> ClientMessage.Attachment(c.requireString("upload_id"), c.string("caption"), clientId)
            "rating_submit" -> ClientMessage.RatingSubmit(
                replyTo = c.requireString("reply_to"),
                score = c.int("score") ?: throw ProtocolException("score: expected an integer"),
                comment = c.string("comment"),
                clientId = clientId,
            )
            else -> throw ProtocolException("type: unknown client message type \"$type\"")
        }
    }

    private companion object {
        val hexColor = Regex("#[0-9A-Fa-f]{6}")
    }
}

/** Thrown inside the parser for a value that breaks the schema; never leaves [ProtocolJson]. */
internal class ProtocolException(message: String) : Exception(message)

private fun String.toJsonObject(): JsonObject = Json.parseToJsonElement(this).asObject("JSON")

private fun JsonElement?.asObject(what: String): JsonObject =
    this as? JsonObject ?: throw ProtocolException("$what: expected an object")

/** The value of [key], or null when it is missing or JSON null. */
private fun JsonObject.present(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

private fun JsonObject.requireString(key: String): String =
    string(key) ?: throw ProtocolException("$key: expected a string")

/** A whole number, written as 5 or 5.0, within ±9·10^15 (where a double still holds every integer). */
private fun JsonObject.long(key: String): Long? {
    val number = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull ?: return null
    return if (number % 1.0 == 0.0 && abs(number) <= 9.0e15) number.toLong() else null
}

private fun JsonObject.int(key: String): Int? = long(key)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()

private fun JsonObject.boolean(key: String): Boolean? =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

private fun JsonObject.requireObject(key: String): JsonObject = this[key].asObject(key)

private fun JsonObject.requireTime(key: String): Long =
    string(key)?.let(Iso8601::parseMillis) ?: throw ProtocolException("$key: expected an ISO 8601 time")

private fun JsonObject.requireArray(key: String): JsonArray =
    this[key] as? JsonArray ?: throw ProtocolException("$key: expected an array")

/** A required array with at least one element: an empty one would leave the user with nothing to press. */
private fun JsonObject.nonEmptyArray(key: String): JsonArray =
    requireArray(key).ifEmpty { throw ProtocolException("$key: expected at least one item") }

private fun JsonObject.section(key: String): JsonObject = this[key] as? JsonObject ?: JsonObject(emptyMap())

private fun JsonArray.strings(): List<String> =
    mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
