package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.protocol.speaks
import ai.clomni.messenger.store.Drafts
import ai.clomni.messenger.store.PendingMessage
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor

/** A short sound of the conversation (DESIGN-PASS-3 A7). */
internal enum class ChatSound { INCOMING, SENT }

/** Runs [action] after [delayMs] on the UI thread; the answer cancels it. */
internal fun interface Scheduler {
    fun after(delayMs: Long, action: () -> Unit): () -> Unit
}

/**
 * Keeps one conversation's screen current and turns taps into engine calls; the Compose view observes it through
 * [onChange]. The screen changes only on [main] (the UI thread); waiting for the engine happens on [worker]. The same
 * behaviour as the iOS SDK's ChatController.
 *
 * [known] is the user's name, email and phone, filled into forms. The typing indicator hides itself after
 * [typingTimeoutMs] (6 s) without a new "typing" from the same sender.
 */
internal class ChatController(
    private val source: ChatDataSource,
    conversationId: String,
    private val language: String?,
    private val worker: Executor,
    private val main: Executor,
    private val scheduler: Scheduler,
    known: Map<String, String> = emptyMap(),
    private val timeZone: TimeZone = TimeZone.getDefault(),
    private val now: () -> Long = System::currentTimeMillis,
    private val typingTimeoutMs: Long = 6_000,
    /** Plays a sound, on [main]; called only while the panel allows sounds. */
    private val playSound: (ChatSound) -> Unit = {},
    /** The timer of the stand-in for the socket ([POLL_MS]); tests keep it apart from the others. */
    private val poll: Scheduler = scheduler,
) {
    /** A message newer than this arrived while the screen was open: it gets the incoming sound. */
    private val openedAt = now()

    private fun sound(sound: ChatSound) {
        if (snapshot.config?.sounds != false) playSound(sound)
    }

    /** Changes when "Yeni söhbət başlat" opens a new conversation in place of a closed one. */
    @Volatile
    var conversationId: String = conversationId
        private set

    var screen: ChatScreen
        private set

    /** Called on [main] after [screen] changed. */
    var onChange: (() -> Unit)? = null

    /** For the theme: the brand's colours and appearance. */
    val config: MessengerConfig? get() = snapshot.config

    /** The offline capsule (CM-077); set from the device's connectivity. */
    var isOffline: Boolean = false
        set(value) {
            field = value
            render()
        }

    private var snapshot = ChatSnapshot(known = known)

    /** Touched on [worker] only. */
    private var observation: UUID? = null
    private var hideTyping: (() -> Unit)? = null

    /** Cancels the next check for messages while the socket is down. */
    private var polling: (() -> Unit)? = null

    /**
     * On [main], while the screen is open: every [POLL_MS] the messages after the last known `seq` are asked for,
     * unless the socket is connected and brings them itself. A socket that cannot connect (a wrong `ws_url`, a proxy)
     * then costs liveliness, not messages.
     */
    private fun schedulePoll() {
        polling?.invoke()
        polling = poll.after(POLL_MS) {
            polling = null
            val id = conversationId
            if (!source.isLive) worker.execute { runCatching { source.loadMessages(id).get() } }
            schedulePoll()
        }
    }

    /** Cancels the wait for a new conversation's flow ([FLOW_WAIT_MS]). */
    private var flowWait: (() -> Unit)? = null

    init {
        // The first frame is the cache's (DESIGN-PASS-3 C5): the store is in memory, so the screen opens as it was left,
        // without a composer that the flow's buttons then take away.
        snapshot = merged(snapshot, read(conversationId))
        screen = ChatPresenter(strings, timeZone, now()).screen(snapshot)
    }

    private val strings: ClomniStrings
        get() = ClomniStrings(snapshot.config.speaks(language), snapshot.config?.strings.orEmpty())

    /** The cache at once, then the server; marks the conversation read. */
    fun load() {
        val id = conversationId
        if (polling == null) schedulePoll()
        worker.execute {
            publish(read(id))
            if (observation == null) observation = source.observe(::changed)
            if (source.conversation(id) == null) runCatching { source.refreshConversation(id).get() }
            val loaded = runCatching { source.loadMessages(id).get() }.isSuccess
            publish(read(id)) {
                snapshot = snapshot.copy(
                    load = when {
                        !loaded -> MessengerSnapshot.Load.FAILED
                        awaitsFlow(id) -> MessengerSnapshot.Load.LOADING.also { waitForFlow(id) }
                        else -> MessengerSnapshot.Load.LOADED
                    },
                )
            }
            source.markRead(id)
        }
    }

    /**
     * A new conversation whose inbox starts with a flow is created at once and its first step comes with it: until then
     * nothing is known about the composer, so the screen waits (C5). Offline, the user may write and queue instead.
     */
    private fun awaitsFlow(id: String): Boolean = Drafts.isDraft(id) && source.config?.startsWithFlow == true && !isOffline

    /** On [main]: after [FLOW_WAIT_MS] without the conversation, the empty draft shows, its composer open. */
    private fun waitForFlow(id: String) {
        flowWait?.invoke()
        flowWait = scheduler.after(FLOW_WAIT_MS) {
            flowWait = null
            if (conversationId == id && snapshot.load == MessengerSnapshot.Load.LOADING) {
                snapshot = snapshot.copy(load = MessengerSnapshot.Load.LOADED)
                render()
            }
        }
    }

    /** "Yenidən cəhd et" after a failed first load. */
    fun retry() {
        main.execute {
            snapshot = snapshot.copy(load = MessengerSnapshot.Load.LOADING)
            render()
            load()
        }
    }

    /** When the screen goes away. */
    fun stop() {
        main.execute {
            hideTyping?.invoke()
            hideTyping = null
            flowWait?.invoke()
            flowWait = null
            polling?.invoke()
            polling = null
        }
        val id = conversationId
        worker.execute {
            observation?.let(source::stopObserving)
            observation = null
            source.setTyping(false, id)
        }
    }

    /** One page further back; [done] hears false at the beginning. */
    fun loadOlder(done: (Boolean) -> Unit) {
        val id = conversationId
        worker.execute {
            val more = runCatching { source.loadOlder(id).get() }.getOrDefault(false)
            publish(read(id), after = { done(more) })
        }
    }

    // The user's actions

    /** False when the text cannot go (blank or over the limit); the composer keeps it then. */
    fun send(text: String): Boolean {
        if (!ChatPresenter.canSend(text, screen.composer.limit)) return false
        val id = conversationId
        val quoted = takeQuote()
        worker.execute {
            runCatching { source.sendText(text, id, quoted).get() }
            source.setTyping(false, id)
        }
        sound(ChatSound.SENT)
        return true
    }

    /**
     * Swipe or "Cavabla": [messageId] is quoted over the field and goes with the next message, text or file; null
     * (the ✕) drops it. On [main].
     */
    fun replyTo(messageId: String?) {
        if (snapshot.replyingTo == messageId) return
        snapshot = snapshot.copy(replyingTo = messageId)
        render()
    }

    /** The quote the composer shows, which the message being sent takes with it. On [main]. */
    private fun takeQuote(): String? {
        val quoted = screen.composer.quote?.messageId ?: return null
        replyTo(null)
        return quoted
    }

    /** The composer's text changed: typing is on while there is some. */
    fun textChanged(text: String) {
        val id = conversationId
        worker.execute { source.setTyping(text.isNotBlank(), id) }
    }

    /** A flow button, or "back" for "← Geri". A second tap finds the buttons gone and does nothing. */
    fun tap(buttonId: String, messageId: String) {
        val message = snapshot.messages.firstOrNull { it.id == messageId } ?: return
        val replies = message.content as? MessageContent.QuickReplies ?: return
        val id = conversationId
        sound(ChatSound.SENT)
        worker.execute {
            runCatching {
                if (buttonId == BACK) {
                    source.goBack(message).get()
                } else {
                    replies.buttons.firstOrNull { it.id == buttonId }?.let { source.reply(message, it).get() }
                }
            }
            publish(read(id))
        }
    }

    /** Sends a form; answers the errors to show by field, empty when it went. */
    fun submit(messageId: String, values: Map<String, String>): Map<String, String> {
        val message = snapshot.messages.firstOrNull { it.id == messageId } ?: return emptyMap()
        val form = message.content as? MessageContent.Form ?: return emptyMap()
        val errors = FormInput.errors(form, values, strings)
        if (errors.isNotEmpty()) return errors
        val id = conversationId
        sound(ChatSound.SENT)
        worker.execute {
            runCatching { source.submitForm(message, FormInput.payload(form, values)).get() }
            publish(read(id))
        }
        return emptyMap()
    }

    /**
     * A rating (CSAT): shown as given at once, then sent through the outbox. Refused (no longer open), the card opens
     * again.
     */
    fun rate(messageId: String, score: Int, comment: String?) {
        val message = snapshot.messages.firstOrNull { it.id == messageId } ?: return
        if (message.content !is MessageContent.Rating) return
        val id = conversationId
        snapshot = snapshot.copy(rated = snapshot.rated + (messageId to (score to comment)))
        render()
        sound(ChatSound.SENT)
        worker.execute {
            val refused = runCatching { source.submitRating(message, score, comment).get() }.isFailure
            publish(read(id)) { if (refused) snapshot = snapshot.copy(rated = snapshot.rated - messageId) }
        }
    }

    /** "Göndərilmədi · Yenidən cəhd et". */
    fun retrySending(clientId: String) {
        worker.execute { runCatching { source.retry(clientId).get() } }
    }

    /** A file to send: its bytes, its name and type, and the caption. */
    class PickedFile(val data: ByteArray, val fileName: String, val mime: String, val caption: String? = null)

    /**
     * An image (already scaled, see [Media.uploadSize]) or a file; [done] hears the text to show when it is refused,
     * or null.
     */
    fun sendFile(data: ByteArray, fileName: String, mime: String, caption: String? = null, done: (String?) -> Unit = {}) =
        attach(done) { PickedFile(data, fileName, mime, caption) }

    /**
     * What the user picked, read by [read] on the worker (decoding and scaling a photo is too slow for the UI thread);
     * null from it means the file could not be read.
     */
    fun attach(done: (String?) -> Unit = {}, read: () -> PickedFile?) {
        val id = conversationId
        val quoted = takeQuote()
        worker.execute {
            val file = runCatching(read).getOrNull()
            val failure = when {
                file == null -> IllegalStateException("unreadable")
                else -> try {
                    source.sendFile(file.data, file.fileName, file.mime, file.caption, id, quoted).get()
                    null
                } catch (e: ExecutionException) {
                    e.cause
                } catch (e: InterruptedException) {
                    e
                }
            }
            main.execute {
                val limits = snapshot.config?.limits
                val image = file != null && Media.isImage(file.mime)
                done(
                    when {
                        failure == null -> null
                        failure is ClomniError.Rejected && failure.message.orEmpty().startsWith("file over") ->
                            strings.format(Key.FILE_TOO_LARGE, if (image) limits?.imageMb ?: 10 else limits?.fileMb ?: 25)
                        else -> strings[Key.ERROR]
                    },
                )
            }
        }
    }

    /**
     * "Yeni söhbət başlat": this screen moves to a new, empty conversation, which the server gets with its first
     * message ([ChatDataSource.draft]). On [main].
     */
    fun startNewConversation() {
        val previous = conversationId
        worker.execute { source.setTyping(false, previous) }
        hideTyping?.invoke()
        hideTyping = null
        val draft = source.draft(null)
        conversationId = draft
        val load = if (awaitsFlow(draft)) MessengerSnapshot.Load.LOADING else MessengerSnapshot.Load.LOADED
        snapshot = ChatSnapshot(config = snapshot.config, known = snapshot.known, load = load)
        if (load == MessengerSnapshot.Load.LOADING) waitForFlow(draft)
        render()
    }

    // The engine's changes (on its thread)

    private fun changed(change: ClomniChange) {
        val id = conversationId
        when (change) {
            is ClomniChange.Messages -> if (change.conversationId == id) {
                worker.execute {
                    val state = read(id)
                    publish(state) { before ->
                        // A message from whoever was typing ends the indicator at once (operator, 2026-10-05).
                        val typing = snapshot.typing
                        val seen = before.messages.mapTo(HashSet()) { it.id }
                        if (typing != null && state.messages.any { it.id !in seen && it.sender.isTyping(typing) }) {
                            hideTyping?.invoke()
                            hideTyping = null
                            snapshot = snapshot.copy(typing = null)
                        }
                        // Something new from the other side while the conversation is on screen.
                        if (state.messages.any {
                                it.id !in seen && it.createdAt >= openedAt && it.sender.type != SenderType.USER && it.type != "system"
                            }
                        ) {
                            sound(ChatSound.INCOMING)
                        }
                    }
                    source.markRead(id)
                }
            }
            // The user's own typing, echoed back, is not someone else writing.
            // "off" ends it whoever it names (operator, 2026-10-06).
            is ClomniChange.Typing -> if (change.conversationId == id && change.sender.type != SenderType.USER) {
                main.execute { showTyping(if (change.isTyping) change.sender else null) }
            }
            // A copy of a message already here changes no message, but the one typing it has stopped. Through the
            // worker, so a new message's own redraw (queued there first) takes the indicator away in the same frame.
            is ClomniChange.Arrived -> if (change.conversationId == id) {
                worker.execute {
                    main.execute {
                        val typing = snapshot.typing
                        if (conversationId == id && typing != null && change.sender.isTyping(typing)) showTyping(null)
                    }
                }
            }
            is ClomniChange.Read -> if (change.conversationId == id) worker.execute { publish(read(id)) }
            ClomniChange.Conversations, ClomniChange.Config, ClomniChange.Session -> worker.execute { publish(read(id)) }
            ClomniChange.News -> Unit
            is ClomniChange.Unread -> Unit
            // This screen's draft is a conversation now: it follows it there.
            is ClomniChange.Started -> if (change.draftId == id) {
                main.execute {
                    if (conversationId == change.draftId) {
                        conversationId = change.conversationId
                        load()
                    }
                }
            }
        }
    }

    /** On [main]. */
    private fun showTyping(sender: Sender?) {
        hideTyping?.invoke()
        hideTyping = null
        snapshot = snapshot.copy(typing = sender)
        render()
        if (snapshot.typing != null) hideTyping = scheduler.after(typingTimeoutMs) { showTyping(null) }
    }

    /** What the engine holds for one conversation; read on [worker]. */
    private class State(
        val conversationId: String,
        val config: MessengerConfig?,
        val conversation: Conversation?,
        val messages: List<Message>,
        val pending: List<PendingMessage>,
        val readUpTo: Long?,
        val answerable: Set<String>,
        val localFiles: Map<String, File>,
    )

    private fun read(id: String): State {
        val messages = source.messages(id)
        val pending = source.pending(id)
        return State(
            conversationId = id,
            config = source.config,
            conversation = source.conversation(id),
            messages = messages,
            pending = pending,
            readUpTo = source.readByOperator(id),
            answerable = messages.filter { it.flow?.interactive == true && source.canAnswer(it) }.mapTo(HashSet()) { it.id },
            localFiles = pending.mapNotNull { entry -> source.localFile(entry)?.let { entry.id to it } }.toMap(),
        )
    }

    /**
     * Hands [state] to the UI thread, applies [update] there (it gets the snapshot from before), redraws, then runs
     * [after]. A state read for the conversation this screen has just left is dropped.
     */
    private fun publish(state: State, after: () -> Unit = {}, update: (ChatSnapshot) -> Unit = {}) {
        main.execute {
            if (state.conversationId == conversationId) {
                val before = snapshot
                snapshot = merged(snapshot, state)
                update(before)
                render()
            }
            after()
        }
    }

    private fun merged(snapshot: ChatSnapshot, state: State) = snapshot.copy(
        config = state.config,
        conversation = state.conversation,
        messages = state.messages,
        pending = state.pending,
        readUpTo = state.readUpTo,
        answerable = state.answerable,
        localFiles = state.localFiles,
    )

    private fun render() {
        snapshot = snapshot.copy(isOffline = isOffline)
        // A flow waiting for a choice: nobody is writing, and a later step must not bring back an old "typing".
        if (snapshot.typing != null && snapshot.awaitsChoice) {
            hideTyping?.invoke()
            hideTyping = null
            snapshot = snapshot.copy(typing = null)
        }
        screen = ChatPresenter(strings, timeZone, now()).screen(snapshot)
        onChange?.invoke()
    }

    private companion object {
        /** The id [QuickReplyBlock.back] carries. */
        const val BACK = "back"

        /** How often the messages are asked for while the socket is not connected. */
        const val POLL_MS = 5_000L

        /** How long a new conversation waits for its flow's first step before it shows empty. */
        const val FLOW_WAIT_MS = 8_000L
    }
}
