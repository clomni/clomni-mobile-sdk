package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * Entry point of the protocol layer (`protocol/schema`): parses what the server sends, encodes what the client sends.
 *
 * Parsing never throws. Fields this SDK does not know are skipped. Broken JSON, or a message that cannot be placed
 * in a conversation, gives null; an unknown type, or a known one with broken content, gives
 * [MessageContent.Unknown] (shown with `fallback_text`); an unknown or broken realtime event gives
 * [RealtimeEvent.Unknown]. Each of these is reported to [logger], meant for the debug log.
 */
public class ProtocolJson(private val logger: (String) -> Unit = {}) {

    /** Null when the message has no id, conversation, `seq` or `created_at`: it cannot be ordered or deduplicated. */
    public fun parseMessage(json: String): Message? = guard("Message") { message(json.toJsonObject()) }

    /** The same, for a message already parsed as part of a larger body (a page of messages). */
    public fun parseMessage(element: JsonElement): Message? = guard("Message") { message(element.asObject("message")) }

    /** Null only when the frame is not JSON or has no event name. */
    public fun parseEvent(json: String): RealtimeEvent? = guard("Realtime frame") {
        val frame = json.toJsonObject()
        event(frame.requireNonEmpty("event"), frame["data"])
    }

    /** Null only when the body is not a JSON object; anything missing or broken inside gets its default. */
    public fun parseConfig(json: String): MessengerConfig? = guard("Config") { config(json.toJsonObject()) }

    /** Null when the payload is not a Clomni push (no `"clomni": "1"`) or lacks a required key. */
    public fun parsePush(json: String): PushPayload? = guard("Push") { push(json.toJsonObject()) }

    public fun encode(message: ClientMessage): String = buildJsonObject {
        put("client_id", message.clientId)
        when (message) {
            is ClientMessage.Text -> {
                put("type", "text")
                putJsonObject("content") { put("text", message.text) }
            }
            is ClientMessage.ButtonReply -> {
                put("type", "button_reply")
                putJsonObject("content") {
                    put("reply_to", message.replyTo)
                    put("button_id", message.buttonId)
                    put("payload", message.payload)
                }
            }
            is ClientMessage.FormSubmit -> {
                put("type", "form_submit")
                putJsonObject("content") {
                    put("reply_to", message.replyTo)
                    put("form_id", message.formId)
                    putJsonObject("values") { message.values.forEach { (key, value) -> put(key, value) } }
                }
            }
            is ClientMessage.Attachment -> {
                put("type", "attachment")
                putJsonObject("content") {
                    put("upload_id", message.uploadId)
                    message.caption?.let { put("caption", it) }
                }
            }
            is ClientMessage.RatingSubmit -> {
                put("type", "rating_submit")
                putJsonObject("content") {
                    put("reply_to", message.replyTo)
                    put("score", message.score)
                    message.comment?.let { put("comment", it) }
                }
            }
        }
    }.toString()

    /** The `content` of a message of [type]: a known content, or [MessageContent.Unknown]. */
    internal fun parseContent(type: String, content: JsonElement?): MessageContent {
        val parse: ((JsonObject) -> MessageContent)? = when (type) {
            "text" -> ::text
            "quick_replies" -> ::quickReplies
            "image" -> ::image
            "file" -> ::file
            "form" -> ::form
            "system" -> ::system
            "card" -> ::card
            "rating" -> ::rating
            else -> null
        }
        if (parse == null) {
            logger("Unknown message type '$type', shown with fallback_text")
            return MessageContent.Unknown(type, content)
        }
        return try {
            parse(content.asObject("content"))
        } catch (e: ProtocolException) {
            logger("Broken '$type' content, shown with fallback_text: ${e.message}")
            MessageContent.Unknown(type, content)
        }
    }

    private inline fun <T : Any> guard(what: String, parse: () -> T?): T? = try {
        parse()
    } catch (e: Exception) {
        logger("$what ignored: ${e.message}")
        null
    }

    // Messages

    private fun message(o: JsonObject): Message {
        val id = o.requireNonEmpty("id")
        val conversationId = o.requireNonEmpty("conversation_id")
        val seq = o.long("seq") ?: throw ProtocolException("'seq' is missing or not an integer")
        val createdAt = o.requireString("created_at")
            .let { Iso8601.parseMillis(it) ?: throw ProtocolException("'created_at' is not a date-time: $it") }
        val type = o.string("type") ?: ""
        return Message(
            id = id,
            clientId = o.string("client_id"),
            conversationId = conversationId,
            type = type,
            sender = (o["sender"] as? JsonObject)?.let(::sender) ?: Sender(SenderType.UNKNOWN),
            createdAt = createdAt,
            seq = seq,
            lang = o.string("lang") ?: "",
            flow = flow(id, o["flow"]),
            content = parseContent(type, o["content"]),
            fallbackText = o.string("fallback_text") ?: "",
        )
    }

    private fun sender(o: JsonObject) =
        Sender(SenderType.from(o.string("type")), o.string("id"), o.string("name"), o.string("avatar_url"))

    private fun flow(messageId: String, element: JsonElement?): FlowRef? {
        if (element == null || element is JsonNull) return null
        return try {
            val o = element.asObject("flow")
            FlowRef(
                flowId = o.requireNonEmpty("flow_id"),
                nodeId = o.requireNonEmpty("node_id"),
                version = o.int("version"),
                interactive = o.boolean("interactive") ?: throw ProtocolException("'interactive' is missing"),
            )
        } catch (e: ProtocolException) {
            logger("Broken flow of $messageId ignored: ${e.message}")
            null
        }
    }

    private fun text(o: JsonObject) = MessageContent.Text(o.requireString("text"))

    private fun quickReplies(o: JsonObject): MessageContent.QuickReplies {
        val buttons = o.requireArray("buttons").map { button(it.asObject("button")) }
        if (buttons.isEmpty()) throw ProtocolException("no buttons")
        return MessageContent.QuickReplies(
            text = o.string("text"),
            buttons = buttons,
            layout = if (o.string("layout") == "chips") QuickRepliesLayout.CHIPS else QuickRepliesLayout.VERTICAL,
            inputDisabled = o.boolean("input_disabled") ?: false,
            allowBack = o.boolean("allow_back") ?: false,
        )
    }

    private fun button(o: JsonObject) =
        Button(o.requireNonEmpty("id"), o.requireNonEmpty("title"), o.string("icon"), o.requireNonEmpty("payload"))

    private fun image(o: JsonObject) = MessageContent.Image(
        url = o.requireNonEmpty("url"),
        thumbUrl = o.string("thumb_url"),
        width = o.int("width")?.takeIf { it > 0 },
        height = o.int("height")?.takeIf { it > 0 },
        caption = o.string("caption"),
    )

    private fun file(o: JsonObject) = MessageContent.File(
        url = o.requireNonEmpty("url"),
        name = o.requireNonEmpty("name"),
        size = o.long("size")?.takeIf { it >= 0 } ?: throw ProtocolException("'size' is missing or negative"),
        mime = o.requireNonEmpty("mime"),
    )

    private fun form(o: JsonObject): MessageContent.Form {
        val fields = o.requireArray("fields").map { formField(it.asObject("field")) }
        if (fields.isEmpty()) throw ProtocolException("no fields")
        return MessageContent.Form(
            text = o.string("text"),
            formId = o.requireNonEmpty("form_id"),
            fields = fields,
            submitTitle = o.requireNonEmpty("submit_title"),
            submitted = (o["submitted"] as? JsonObject)?.toStringMap(),
        )
    }

    private fun formField(o: JsonObject): FormField {
        val key = o.requireNonEmpty("key")
        val type = o.requireString("type")
        val options = (o["options"] as? JsonArray)?.map {
            val option = it.asObject("option")
            FormField.Option(option.requireString("value"), option.requireString("label"))
        }
        if (type == "select" && options == null) throw ProtocolException("select field '$key' has no options")
        return FormField(
            key = key,
            type = FormFieldType.from(type),
            label = o.requireString("label"),
            required = o.boolean("required") ?: false,
            maxLength = o.int("max_length")?.takeIf { it > 0 },
            defaultCountry = o.string("default_country"),
            placeholder = o.string("placeholder"),
            options = options.orEmpty(),
        )
    }

    private fun system(o: JsonObject) =
        MessageContent.System(o.requireString("event"), o.requireString("text"), o.int("position")?.takeIf { it > 0 })

    private fun card(o: JsonObject): MessageContent.Card {
        val cards = o.requireArray("cards").map { cardItem(it.asObject("card")) }
        if (cards.isEmpty()) throw ProtocolException("no cards")
        return MessageContent.Card(cards)
    }

    private fun cardItem(o: JsonObject) = CardItem(
        imageUrl = o.string("image_url"),
        title = o.requireString("title"),
        subtitle = o.string("subtitle"),
        buttons = (o["buttons"] as? JsonArray)?.map { cardButton(it.asObject("card button")) }.orEmpty(),
    )

    private fun cardButton(o: JsonObject): CardButton {
        val payload = o.string("payload")
        val url = o.string("url")
        if ((payload == null) == (url == null)) throw ProtocolException("a card button needs either payload or url")
        return CardButton(o.requireString("id"), o.requireString("title"), payload, url)
    }

    private fun rating(o: JsonObject): MessageContent.Rating {
        val scale = o.requireString("scale")
        return MessageContent.Rating(
            text = o.requireString("text"),
            scale = RatingScale.from(scale) ?: throw ProtocolException("unknown scale '$scale'"),
            comment = RatingComment.from(o.string("comment")),
            submitted = (o["submitted"] as? JsonObject)?.toStringMap(),
        )
    }

    // Realtime events

    private fun event(name: String, data: JsonElement?): RealtimeEvent {
        val parse: ((JsonObject) -> RealtimeEvent)? = when (name) {
            "ready" -> ::ready
            "message.created" -> { d -> RealtimeEvent.MessageCreated(message(d)) }
            "message.updated" -> { d -> RealtimeEvent.MessageUpdated(message(d)) }
            "typing" -> ::typing
            "read" -> ::read
            "conversation.updated" -> ::conversationUpdated
            "unread.changed" -> { d ->
                RealtimeEvent.UnreadChanged(d.int("total")?.takeIf { it >= 0 } ?: throw ProtocolException("no total"))
            }
            "config.changed" -> { d -> RealtimeEvent.ConfigChanged(d.requireNonEmpty("etag")) }
            else -> null
        }
        if (parse == null) {
            logger("Unknown realtime event '$name' ignored")
            return RealtimeEvent.Unknown(name)
        }
        return try {
            parse(data.asObject("data"))
        } catch (e: ProtocolException) {
            logger("Broken realtime event '$name' ignored: ${e.message}")
            RealtimeEvent.Unknown(name)
        }
    }

    private fun ready(d: JsonObject) = RealtimeEvent.Ready(
        userId = d.requireNonEmpty("user_id"),
        heartbeatSec = d.int("heartbeat_sec")?.takeIf { it > 0 } ?: throw ProtocolException("no heartbeat_sec"),
    )

    private fun typing(d: JsonObject): RealtimeEvent.Typing {
        val state = d.requireString("state")
        return RealtimeEvent.Typing(
            conversationId = d.requireNonEmpty("conversation_id"),
            sender = sender(d["sender"].asObject("sender")),
            isTyping = when (state) {
                "on" -> true
                "off" -> false
                else -> throw ProtocolException("unknown typing state '$state'")
            },
        )
    }

    private fun read(d: JsonObject) = RealtimeEvent.Read(
        conversationId = d.requireNonEmpty("conversation_id"),
        upToSeq = d.long("up_to_seq") ?: throw ProtocolException("no up_to_seq"),
        by = SenderType.from(d.requireString("by")),
    )

    private fun conversationUpdated(d: JsonObject) = RealtimeEvent.ConversationUpdated(
        id = d.requireNonEmpty("id"),
        status = ConversationStatus.from(d.requireString("status")),
        assignee = (d["assignee"] as? JsonObject)?.let {
            Assignee(it.requireString("name"), it.string("avatar_url"), it.boolean("online") ?: false)
        },
        unreadCount = d.int("unread_count"),
    )

    // Config and push

    private fun config(o: JsonObject): MessengerConfig {
        val brand = o.objectOrEmpty("brand")
        val launcher = o.objectOrEmpty("launcher")
        val home = o.objectOrEmpty("home")
        val team = o.objectOrEmpty("team")
        val composer = o.objectOrEmpty("composer")
        val limits = o.objectOrEmpty("limits")
        return MessengerConfig(
            brand = MessengerConfig.Brand(
                name = brand.string("name") ?: "",
                logoUrl = brand.string("logo_url"),
                primaryColor = brand.string("primary_color").let {
                    if (it != null && hexColor.matches(it)) {
                        it
                    } else {
                        logger("brand.primary_color '$it' is not #RRGGBB, using ${MessengerConfig.DEFAULT_PRIMARY_COLOR}")
                        MessengerConfig.DEFAULT_PRIMARY_COLOR
                    }
                },
                onPrimaryColor = brand.string("on_primary_color")?.takeIf { hexColor.matches(it) },
                theme = when (brand.string("theme")) {
                    "light" -> MessengerConfig.Theme.LIGHT
                    "dark" -> MessengerConfig.Theme.DARK
                    else -> MessengerConfig.Theme.SYSTEM
                },
            ),
            launcher = MessengerConfig.Launcher(
                visible = launcher.boolean("visible") ?: false,
                position = if (launcher.string("position") == "left") {
                    MessengerConfig.LauncherPosition.LEFT
                } else {
                    MessengerConfig.LauncherPosition.RIGHT
                },
                bottomPadding = launcher.int("bottom_padding")?.takeIf { it >= 0 } ?: 0,
                icon = launcher.string("icon") ?: "default",
            ),
            home = MessengerConfig.Home(
                greetingTitle = home.string("greeting_title"),
                greetingSubtitle = home.string("greeting_subtitle"),
                showTeamAvatars = home.boolean("show_team_avatars") ?: false,
                channels = (home["channels"] as? JsonArray)?.mapNotNull { element ->
                    val channel = element as? JsonObject ?: return@mapNotNull null
                    val type = channel.string("type") ?: return@mapNotNull null
                    channel.string("url")?.let { MessengerConfig.HomeChannel(type, it) }
                }.orEmpty(),
                cards = (home["cards"] as? JsonArray)?.strings()?.mapNotNull {
                    when (it) {
                        "recent_conversation" -> MessengerConfig.HomeCard.RECENT_CONVERSATION
                        "new_conversation" -> MessengerConfig.HomeCard.NEW_CONVERSATION
                        else -> null
                    }
                } ?: MessengerConfig.HomeCard.entries,
            ),
            team = MessengerConfig.Team(
                avatars = (team["avatars"] as? JsonArray)?.strings().orEmpty(),
                replyTime = team.string("reply_time"),
                officeHours = (team["office_hours"] as? JsonObject)?.let {
                    MessengerConfig.OfficeHours(it.string("tz"), it.boolean("open_now"))
                },
            ),
            bot = o.objectOrEmpty("bot").let { MessengerConfig.Bot(it.string("name") ?: "", it.string("avatar_url")) },
            composer = MessengerConfig.Composer(
                placeholder = composer.string("placeholder"),
                attachments = composer.boolean("attachments") ?: true,
                emoji = composer.boolean("emoji") ?: true,
            ),
            languages = (o["languages"] as? JsonArray)?.strings().orEmpty()
                .filter { it in supportedLanguages }.distinct().ifEmpty { listOf("az") },
            strings = (o["strings"] as? JsonObject)?.let { strings ->
                strings.keys.mapNotNull { key -> strings.string(key)?.let { key to it } }.toMap()
            }.orEmpty(),
            limits = MessengerConfig.Limits(
                imageMb = limits.int("image_mb")?.takeIf { it > 0 } ?: 10,
                fileMb = limits.int("file_mb")?.takeIf { it > 0 } ?: 25,
                textChars = limits.int("text_chars")?.takeIf { it > 0 } ?: ClientMessage.MAX_TEXT_LENGTH,
            ),
        )
    }

    private fun push(o: JsonObject): PushPayload? {
        if (o.string("clomni") != "1") return null
        return PushPayload(
            type = o.requireNonEmpty("type"),
            conversationId = o.requireNonEmpty("conversation_id"),
            messageId = o.string("message_id"),
            title = o.requireString("title"),
            body = o.requireString("body"),
            avatarUrl = o.string("avatar_url"),
            // FCM data values are always strings.
            unreadTotal = o.int("unread_total") ?: o.string("unread_total")?.toIntOrNull(),
        )
    }

    private companion object {
        val hexColor = Regex("#[0-9A-Fa-f]{6}")
        val supportedLanguages = setOf("az", "en", "ru")
    }
}

/** Thrown inside the parser for a value that breaks the schema; never leaves [ProtocolJson]. */
internal class ProtocolException(message: String) : Exception(message)

private fun String.toJsonObject(): JsonObject = Json.parseToJsonElement(this).asObject("JSON")

private fun JsonElement?.asObject(what: String): JsonObject =
    this as? JsonObject ?: throw ProtocolException("$what is not an object")

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

private fun JsonObject.requireString(key: String): String =
    string(key) ?: throw ProtocolException("'$key' is missing or not a string")

private fun JsonObject.requireNonEmpty(key: String): String =
    requireString(key).ifEmpty { throw ProtocolException("'$key' is empty") }

private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull

private fun JsonObject.int(key: String): Int? = long(key)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()

private fun JsonObject.boolean(key: String): Boolean? =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

private fun JsonObject.requireArray(key: String): JsonArray =
    this[key] as? JsonArray ?: throw ProtocolException("'$key' is missing or not an array")

private fun JsonObject.objectOrEmpty(key: String): JsonObject = this[key] as? JsonObject ?: JsonObject(emptyMap())

private fun JsonArray.strings(): List<String> = mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }

/** Submitted form or rating values, for display: numbers and booleans as their text, null values left out. */
private fun JsonObject.toStringMap(): Map<String, String> = entries.mapNotNull { (key, value) ->
    when (value) {
        is JsonNull -> null
        is JsonPrimitive -> key to value.content
        else -> key to value.toString()
    }
}.toMap()
