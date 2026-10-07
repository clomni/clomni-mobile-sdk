package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.Assignee
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.ConversationStatus
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.ReplyRef
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import java.util.Locale
import java.util.TimeZone

/** Builds the conversation screen from a [ChatSnapshot]; the same rules as the iOS SDK's ChatPresenter. */
internal class ChatPresenter(
    val strings: ClomniStrings,
    timeZone: TimeZone = TimeZone.getDefault(),
    private val now: Long,
) {
    private val time = TimeText(strings, timeZone)

    fun screen(snapshot: ChatSnapshot): ChatScreen {
        val hasContent = snapshot.messages.isNotEmpty() || snapshot.pending.isNotEmpty()
        val phase = when {
            hasContent || snapshot.load == MessengerSnapshot.Load.LOADED -> HomeScreen.Phase.READY
            snapshot.load == MessengerSnapshot.Load.FAILED -> HomeScreen.Phase.FAILED
            else -> HomeScreen.Phase.LOADING
        }
        val lastIncoming = snapshot.messages.lastOrNull { it.sender.type != SenderType.USER && it.type != "system" }
        val composer = composer(snapshot, phase == HomeScreen.Phase.READY)
        // No reply while a flow waits for a choice: there is no composer to write the answer in.
        val canReply = composer.mode == ChatComposer.Mode.Open
        return ChatScreen(
            phase = phase,
            loadingLabel = strings[Key.LOADING],
            header = header(snapshot),
            items = items(snapshot, canReply),
            composer = composer,
            offline = if (snapshot.isOffline) strings[Key.OFFLINE] else null,
            connected = strings[Key.CONNECTED],
            failure = if (phase == HomeScreen.Phase.FAILED) HomeScreen.Failure(strings[Key.ERROR], strings[Key.RETRY]) else null,
            announcement = lastIncoming?.let { Announcement(it.id, label(it, snapshot)) },
            replyLabel = strings[Key.REPLY],
            copyLabel = strings[Key.COPY],
            newMessageLabel = strings[Key.NEW_MESSAGE],
        )
    }

    // Header

    private fun header(snapshot: ChatSnapshot): ChatHeader {
        val config = snapshot.config
        val brand = config?.brand?.name.orEmpty()
        val conversation = snapshot.conversation
        val status = conversation?.status
        // Who answers: the assignee; without one, the last operator who wrote (no dot: nothing says they are online).
        val assignee = conversation?.assignee ?: snapshot.messages.lastOrNull { it.sender.type == SenderType.OPERATOR && !it.sender.name.isNullOrEmpty() }
            ?.sender?.let { Assignee(it.name!!, it.avatarUrl, online = false) }
        if (assignee != null) {
            val online = assignee.online ?: true
            return ChatHeader(
                lead = ChatHeader.Lead.Person(ChatAvatar(assignee.avatarUrl, initial(assignee.name), false), online),
                title = assignee.name,
                // Only the company: being online is the green dot on the avatar, not a word (operator, 2026-10-05).
                subtitle = brand,
                backLabel = strings[Key.GO_BACK],
                closeLabel = strings[Key.CLOSE],
            )
        }
        val hours = config?.team?.officeHours
        val subtitle = when {
            hours?.openNow == false ->
                hours.nextOpenAt?.let { strings.format(Key.AWAY_UNTIL, time.upcoming(it, now)) } ?: strings[Key.AWAY]
            status == ConversationStatus.QUEUED -> config?.team?.replyTime ?: strings[Key.HEADER_SUBTITLE]
            else -> strings[Key.HEADER_SUBTITLE]
        }
        // No operator has taken it or written (the bot or a flow answers): the company, by its logo and name.
        return ChatHeader(
            ChatHeader.Lead.Brand(ChatAvatar(config?.brand?.logoUrl, initial(brand), true)),
            brand,
            subtitle,
            strings[Key.GO_BACK],
            strings[Key.CLOSE],
        )
    }

    private fun teamAvatars(config: MessengerConfig?): List<String> =
        if (config?.team?.show == false) emptyList() else config?.team?.avatars.orEmpty().take(3)

    // Composer

    private fun composer(snapshot: ChatSnapshot, known: Boolean): ChatComposer {
        val config = snapshot.config
        val mode = when {
            // Not "shown" by default (DESIGN-PASS-3 C5): until the messages and their buttons are known there is none,
            // so a flow's step never finds one to take away.
            !known -> ChatComposer.Mode.Hidden
            snapshot.conversation?.status == ConversationStatus.CLOSED ->
                ChatComposer.Mode.Closed(strings[Key.CLOSED], strings[Key.START_NEW_CONVERSATION])
            // The server says whether a flow drives the conversation (conversation.flow): while it waits for a button,
            // a form or its next step there is no field; it waits for typed text, or it is over, and the field is back.
            snapshot.conversation?.flow?.holdsComposer == true -> ChatComposer.Mode.Hidden
            else -> ChatComposer.Mode.Open
        }
        return ChatComposer(
            mode = mode,
            placeholder = strings[Key.COMPOSER_PLACEHOLDER],
            showsAttach = config?.composer?.attachments ?: true,
            showsEmoji = config?.composer?.emoji ?: true,
            limit = config?.limits?.textChars ?: 4_000,
            sendLabel = strings[Key.SEND],
            attachLabel = strings[Key.ATTACH],
            emojiLabel = strings[Key.EMOJI],
            mediaLabel = strings[Key.PICK_MEDIA],
            cameraLabel = strings[Key.PICK_CAMERA],
            fileLabel = strings[Key.PICK_FILE],
            removeLabel = strings[Key.REMOVE_ATTACHMENT],
            quote = snapshot.replyingTo.takeIf { mode == ChatComposer.Mode.Open }
                ?.let { id -> snapshot.messages.firstOrNull { it.id == id } }
                ?.let { quote(it, snapshot) },
            cancelQuoteLabel = strings[Key.CLOSE],
        )
    }

    // Transcript

    /** A bubble before the runs are known. */
    private data class Draft(
        val id: String,
        val side: Bubble.Side,
        /** Same key, same run. */
        val sender: String,
        val date: Long,
        val body: Bubble.Body,
        val avatar: ChatAvatar?,
        val metaName: String?,
        val status: Bubble.Status?,
        val accessibilityLabel: String,
        val quote: Bubble.Quote? = null,
        val messageId: String? = null,
        val replyable: Boolean = false,
        val copyText: String? = null,
        /** Who wrote it; null for the user's pending messages. */
        val from: Sender? = null,
    )

    private sealed interface Entry {
        data class Time(val id: String, val text: String) : Entry
        data class Draw(val draft: Draft) : Entry
        data class System(val line: SystemLine) : Entry
        data class Replies(val block: QuickReplyBlock) : Entry
        data class Typing(val line: TypingLine) : Entry
    }

    private fun items(snapshot: ChatSnapshot, canReply: Boolean): List<ChatItem> {
        val entries = mutableListOf<Entry>()
        var previous: Long? = null
        fun separate(id: String, date: Long) {
            val last = previous
            if (last == null || date - last > SEPARATOR_PAUSE_MS) entries += Entry.Time("time-$id", time.day(date, now))
            previous = date
        }

        for (message in snapshot.messages) {
            separate(key(message), message.createdAt)
            val content = message.content
            if (content is MessageContent.System) {
                entries += Entry.System(SystemLine(message.id, content.text, systemAvatars(content.event, snapshot)))
                continue
            }
            body(message, snapshot)?.let { body ->
                entries += Entry.Draw(
                    draft(message, body, snapshot).copy(
                        quote = message.replyTo?.let { quote(it, snapshot) },
                        messageId = message.id,
                        replyable = canReply && body !is FormCard,
                        copyText = copyText(message.content),
                    ),
                )
            }
            if (content is MessageContent.QuickReplies && message.id in snapshot.answerable) {
                entries += Entry.Replies(block(message.id, content))
            }
        }
        for (pending in snapshot.pending) {
            val body = body(pending, snapshot) ?: continue
            separate(pending.id, pending.createdAt)
            val text = pending.preview ?: pending.upload?.fileName ?: strings[Key.BACK]
            entries += Entry.Draw(
                Draft(
                    pending.id, Bubble.Side.OUTGOING, "user", pending.createdAt, body, null, null, status(pending),
                    "${strings[Key.YOU]}, ${time.clock(pending.createdAt)}: $text",
                    quote = quoted(pending.message)?.let { id ->
                        snapshot.messages.firstOrNull { it.id == id }?.let { quote(it, snapshot) }
                            ?: Bubble.Quote(id, "", strings[Key.QUOTE_DELETED])
                    },
                    copyText = (pending.message as? ClientMessage.Text)?.text ?: (pending.message as? ClientMessage.Attachment)?.caption,
                ),
            )
        }
        // A row of its own at the end; none while a flow waits for a choice.
        snapshot.typing?.takeUnless { snapshot.awaitsChoice }?.let { sender ->
            val who = person(sender, snapshot)
            // One face: the run the typing continues gives its avatar to the typing row.
            val last = (entries.lastOrNull() as? Entry.Draw)?.draft
            if (last?.from?.isTyping(sender) == true) entries[entries.lastIndex] = Entry.Draw(last.copy(avatar = null))
            entries += Entry.Typing(TypingLine(who.second, "${who.first} ${strings[Key.TYPING]}"))
        }
        markStatuses(entries, snapshot)
        return runs(entries)
    }

    /**
     * Every message of the user carries its mark next to its time, inside the bubble (G7): the clock while it goes,
     * then ✓, then ✓✓ once read; TalkBack reads "Göndərilir", "Göndərildi" or "Oxundu". A failure stays in words.
     */
    private fun markStatuses(entries: MutableList<Entry>, snapshot: ChatSnapshot) {
        val pending = snapshot.pending.mapTo(HashSet()) { it.id }
        val seqs = snapshot.messages.associate { key(it) to it.seq }
        entries.forEachIndexed { index, entry ->
            val draft = (entry as? Entry.Draw)?.draft ?: return@forEachIndexed
            if (draft.side != Bubble.Side.OUTGOING || draft.status != null) return@forEachIndexed
            val mark = when {
                draft.id in pending -> Bubble.Status.Mark.SENDING
                snapshot.readUpTo?.let { it >= (seqs[draft.id] ?: 0L) } == true -> Bubble.Status.Mark.READ
                else -> Bubble.Status.Mark.SENT
            }
            val text = when (mark) {
                Bubble.Status.Mark.SENDING -> strings[Key.SENDING]
                Bubble.Status.Mark.SENT -> strings[Key.SENT]
                Bubble.Status.Mark.READ -> strings[Key.READ]
            }
            entries[index] = Entry.Draw(draft.copy(status = Bubble.Status(text, isFailure = false, retryId = null, mark = mark)))
        }
    }

    /** Bubbles of one sender within a minute of each other, with nothing between them, form a run. */
    private fun runs(entries: List<Entry>): List<ChatItem> {
        val items = mutableListOf<ChatItem>()
        var index = 0
        while (index < entries.size) {
            val first = (entries[index] as? Entry.Draw)?.draft
            if (first == null) {
                entries[index].item()?.let { items += it }
                index++
                continue
            }
            val run = mutableListOf(first)
            while (index + run.size < entries.size) {
                val next = (entries[index + run.size] as? Entry.Draw)?.draft ?: break
                if (next.sender != first.sender || next.date - run.last().date > GROUP_WINDOW_MS) break
                run += next
            }
            run.forEachIndexed { offset, draft ->
                val position = when {
                    run.size == 1 -> Bubble.Position.SINGLE
                    offset == 0 -> Bubble.Position.FIRST
                    offset == run.size - 1 -> Bubble.Position.LAST
                    else -> Bubble.Position.MIDDLE
                }
                val closesRun = offset == run.size - 1 && draft.side == Bubble.Side.INCOMING
                val opensRun = offset == 0 && draft.side == Bubble.Side.INCOMING
                items += ChatItem.BubbleItem(
                    Bubble(
                        draft.id, draft.side, draft.body, position,
                        avatar = if (closesRun) draft.avatar else null,
                        time = time.clock(draft.date),
                        status = draft.status,
                        accessibilityLabel = draft.accessibilityLabel,
                        author = if (opensRun) draft.metaName else null,
                        quote = draft.quote,
                        messageId = draft.messageId,
                        replyable = draft.replyable,
                        copyText = draft.copyText,
                    ),
                )
            }
            index += run.size
        }
        return items
    }

    /** Everything but a bubble, which takes its place in a run first. */
    private fun Entry.item(): ChatItem? = when (this) {
        is Entry.Time -> ChatItem.TimeItem(id, text)
        is Entry.System -> ChatItem.SystemItem(line)
        is Entry.Replies -> ChatItem.RepliesItem(block)
        is Entry.Typing -> ChatItem.TypingItem(line)
        is Entry.Draw -> null
    }

    /**
     * A message's place in the transcript: its `client_id` when it has one, so the user's message keeps it from the
     * moment it is written to the server's copy, and only its status changes; otherwise its id.
     */
    private fun key(message: Message): String = message.clientId ?: message.id

    private fun draft(message: Message, body: Bubble.Body, snapshot: ChatSnapshot): Draft {
        val outgoing = message.sender.type == SenderType.USER
        val (name, avatar) = person(message.sender, snapshot)
        return Draft(
            id = key(message),
            side = if (outgoing) Bubble.Side.OUTGOING else Bubble.Side.INCOMING,
            sender = if (outgoing) "user" else "${message.sender.type.wire} ${message.sender.id ?: message.sender.name.orEmpty()}",
            date = message.createdAt,
            body = body,
            avatar = if (outgoing) null else avatar,
            metaName = when {
                outgoing -> null
                else -> name
            },
            status = null,
            accessibilityLabel = label(message, snapshot),
            from = message.sender,
        )
    }

    /** "Clomni bot, 10:30: Salam…" (brief 8·7.6). */
    private fun label(message: Message, snapshot: ChatSnapshot): String {
        val who = when (message.sender.type) {
            SenderType.USER -> strings[Key.YOU]
            SenderType.BOT -> "${person(message.sender, snapshot).first} ${strings[Key.BOT].lowercase(Locale.ROOT)}"
            else -> person(message.sender, snapshot).first
        }
        return "$who, ${time.clock(message.createdAt)}: ${readable(message)}"
    }

    // Replies

    /** The server's description of the quoted message. */
    private fun quote(ref: ReplyRef, snapshot: ChatSnapshot): Bubble.Quote = Bubble.Quote(
        ref.id,
        ref.sender?.let { author(it, snapshot) }.orEmpty(),
        ref.excerpt?.let(::oneLine)?.takeIf { it.isNotEmpty() } ?: strings[Key.QUOTE_DELETED],
    )

    /** A message here being quoted: over the field, and in the user's bubble until the server's copy comes. */
    private fun quote(message: Message, snapshot: ChatSnapshot): Bubble.Quote {
        val excerpt = when (val content = message.content) {
            is MessageContent.Image -> content.caption ?: strings[Key.IMAGE]
            is MessageContent.File -> content.name
            else -> readable(message)
        }
        return Bubble.Quote(message.id, author(message.sender, snapshot), oneLine(excerpt).take(EXCERPT_CHARS))
    }

    private fun author(sender: Sender, snapshot: ChatSnapshot): String =
        if (sender.type == SenderType.USER) strings[Key.YOU] else person(sender, snapshot).first

    private fun oneLine(text: String): String = text.replace(Regex("\\s+"), " ").trim()

    private fun quoted(message: ClientMessage): String? = when (message) {
        is ClientMessage.Text -> message.replyTo
        is ClientMessage.Attachment -> message.replyTo
        else -> null
    }

    private fun copyText(content: MessageContent): String? = when (content) {
        is MessageContent.Text -> LimitedMarkdown.plainText(content.text)
        is MessageContent.Image -> content.caption
        is MessageContent.QuickReplies -> content.text?.let(LimitedMarkdown::plainText)
        else -> null
    }

    private fun readable(message: Message): String = when (val content = message.content) {
        is MessageContent.Text -> LimitedMarkdown.plainText(content.text)
        is MessageContent.Image -> strings[Key.IMAGE] + (content.caption?.let { ": $it" } ?: "")
        is MessageContent.File ->
            "${strings[Key.FILE]}: ${content.name}, ${Media.fileSize(content.size, strings.language)}"
        is MessageContent.QuickReplies -> content.text?.let(LimitedMarkdown::plainText) ?: message.fallbackText
        is MessageContent.Form -> content.text?.let(LimitedMarkdown::plainText) ?: message.fallbackText
        else -> message.fallbackText
    }

    /** What a message shows in its bubble; null for quick replies without text (only the buttons show). */
    private fun body(message: Message, snapshot: ChatSnapshot): Bubble.Body? = when (val content = message.content) {
        is MessageContent.Text -> Bubble.TextBody(LimitedMarkdown.parse(content.text))
        is MessageContent.QuickReplies -> content.text?.let { Bubble.TextBody(LimitedMarkdown.parse(it)) }
        is MessageContent.Image -> {
            val box = Media.imageBox(content.width, content.height)
            Bubble.ImageBody(
                url = content.thumbUrl ?: content.url,
                fullUrl = content.url,
                localFile = null,
                width = box.width,
                height = box.height,
                sizeKnown = box.known,
                caption = content.caption?.let(LimitedMarkdown::parse),
            )
        }
        is MessageContent.File -> Bubble.FileBody(
            content.name,
            Media.fileSize(content.size, strings.language),
            Media.fileIcon(content.mime),
            content.url,
        )
        is MessageContent.Form -> card(message, content, snapshot)
        is MessageContent.System -> null
        // Phase 2 types and anything unknown read as a plain bot bubble with the fallback text.
        is MessageContent.Card, is MessageContent.Rating, is MessageContent.Unknown ->
            Bubble.TextBody(listOf(TextRun(message.fallbackText)))
    }

    /**
     * A pending message's bubble: its text, the button's title, "← Geri", or the file being sent. A submitted form or
     * rating has none: the form itself shows it was sent.
     */
    private fun body(pending: PendingMessage, snapshot: ChatSnapshot): Bubble.Body? =
        when (val message = pending.message) {
            is ClientMessage.Text -> Bubble.TextBody(listOf(TextRun(message.text)))
            is ClientMessage.ButtonReply -> Bubble.TextBody(listOf(TextRun(pending.preview ?: strings[Key.BACK])))
            is ClientMessage.Attachment -> {
                val upload = pending.upload
                when {
                    upload == null -> message.caption?.let { Bubble.TextBody(listOf(TextRun(it))) }
                    Media.isImage(upload.mime) -> {
                        val box = Media.imageBox(null, null)
                        Bubble.ImageBody(
                            url = null,
                            fullUrl = null,
                            localFile = snapshot.localFiles[pending.id],
                            width = box.width,
                            height = box.height,
                            sizeKnown = false,
                            caption = message.caption?.let { listOf(TextRun(it)) },
                        )
                    }
                    else -> Bubble.FileBody(
                        upload.fileName,
                        Media.fileSize(upload.size, strings.language),
                        Media.fileIcon(upload.mime),
                        null,
                    )
                }
            }
            is ClientMessage.FormSubmit, is ClientMessage.RatingSubmit -> null
        }

    private fun status(pending: PendingMessage): Bubble.Status? {
        if (pending.state != PendingMessage.State.FAILED) return null
        return Bubble.Status("${strings[Key.FAILED]} · ${strings[Key.RETRY]}", isFailure = true, retryId = pending.id)
    }

    private fun block(messageId: String, replies: MessageContent.QuickReplies): QuickReplyBlock {
        val buttons = replies.buttons.mapIndexed { index, button ->
            val title = listOfNotNull(button.icon, button.title).joinToString(" ")
            ReplyButton(button.id, title, strings.buttonPosition(button.title, index + 1, replies.buttons.size))
        }
        // The flow's own "Yenidən başla" (or back) button already takes the user back: no second one from the SDK.
        val back = if (replies.allowBack && replies.buttons.none { restartTitle(it.title) }) {
            ReplyButton("back", strings[Key.BACK], strings[Key.GO_BACK])
        } else {
            null
        }
        return QuickReplyBlock(messageId, replies.layout, buttons, back)
    }

    private fun restartTitle(title: String): Boolean =
        title.lowercase(Locale.ROOT).filter { it.isLetter() || it == ' ' }.trim().replace(Regex("\\s+"), " ") in RESTART_TITLES

    private fun card(message: Message, form: MessageContent.Form, snapshot: ChatSnapshot): FormCard {
        val messageId = message.id
        val prefill = FormInput.prefill(form, snapshot.known)
        val sent = form.submitted != null
        return FormCard(
            messageId = messageId,
            text = form.text?.let(LimitedMarkdown::parse),
            textAccessibilityLabel = label(message, snapshot),
            fields = form.fields.map { field ->
                FormCard.Field(
                    id = field.key,
                    type = field.type,
                    label = field.label,
                    required = field.required,
                    accessibilityLabel = if (field.required) "${field.label}, ${strings[Key.REQUIRED]}" else field.label,
                    placeholder = field.placeholder,
                    maxLength = field.maxLength,
                    options = field.options,
                    initialValue = prefill[field.key].orEmpty(),
                    shownLabel = if (field.required) field.label else "${field.label} ${strings[Key.OPTIONAL]}",
                )
            },
            submitTitle = form.submitTitle,
            readOnly = sent || messageId !in snapshot.answerable,
            submitted = FormInput.submittedLines(form).map { (label, value) -> FormCard.Line(label, value) },
            sentLabel = if (sent) strings[Key.SENT] else null,
        )
    }

    private fun systemAvatars(event: MessageContent.SystemEvent, snapshot: ChatSnapshot): List<ChatAvatar> =
        when (event) {
            MessageContent.SystemEvent.OperatorJoined -> listOfNotNull(
                snapshot.conversation?.assignee?.let { ChatAvatar(it.avatarUrl, initial(it.name), false) },
            )
            MessageContent.SystemEvent.WaitingInQueue, MessageContent.SystemEvent.AssignedToTeam ->
                teamAvatars(snapshot.config).map { ChatAvatar(it, "", false) }
            else -> emptyList()
        }

    /** The name and face of a sender as the conversation shows them. */
    private fun person(sender: Sender, snapshot: ChatSnapshot): Pair<String, ChatAvatar> {
        val config = snapshot.config
        val brand = config?.brand?.name.orEmpty()
        return when (sender.type) {
            SenderType.BOT -> {
                // The bot speaks as the brand (DESIGN-PASS-3 B2): its own name in the panel is not shown.
                val name = brand.ifEmpty { sender.name ?: config?.bot?.name.orEmpty() }
                name to ChatAvatar(config?.brand?.logoUrl ?: config?.bot?.avatarUrl ?: sender.avatarUrl, initial(name), true)
            }
            SenderType.OPERATOR -> {
                val assignee = snapshot.conversation?.assignee
                val name = sender.name ?: assignee?.name ?: brand
                name to ChatAvatar(sender.avatarUrl ?: assignee?.avatarUrl, initial(name), false)
            }
            SenderType.USER -> strings[Key.YOU] to ChatAvatar(null, initial(strings[Key.YOU]), false)
            SenderType.SYSTEM, SenderType.UNKNOWN -> brand to ChatAvatar(null, initial(brand), true)
        }
    }

    private fun initial(name: String): String =
        if (name.isEmpty()) "" else String(Character.toChars(name.codePointAt(0))).uppercase(Locale.ROOT)

    companion object {
        /** Messages of one sender less than this far apart share a run: one avatar, one meta line. */
        const val GROUP_WINDOW_MS = 60_000L

        /** The server's excerpts are at most this long; a local quote is cut to the same. */
        private const val EXCERPT_CHARS = 120

        /** A longer pause gets a new time separator. */
        const val SEPARATOR_PAUSE_MS = 3_600_000L

        /** A flow button with one of these titles (letters only, lower case) restarts or steps back by itself. */
        private val RESTART_TITLES = setOf(
            "yenidən başla", "yenidən başlat", "əvvələ qayıt", "başa qayıt", "geri", "geri qayıt",
            "start over", "restart", "back", "go back", "начать заново", "сначала", "назад",
        )

        /** The send button shows for text that is not blank and within the limit. */
        fun canSend(text: String, limit: Int): Boolean {
            val trimmed = text.trim()
            return trimmed.isNotEmpty() && trimmed.codePointCount(0, trimmed.length) <= limit
        }
    }
}
