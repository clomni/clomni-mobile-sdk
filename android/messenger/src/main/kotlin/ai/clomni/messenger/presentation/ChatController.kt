package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.store.PendingMessage
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor

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
 * [typingTimeoutMs] (8 s) without news.
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
    private val typingTimeoutMs: Long = 8_000,
) {
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

    /** The thin yellow strip; set from the device's connectivity. */
    var isOffline: Boolean = false
        set(value) {
            field = value
            render()
        }

    private var snapshot = ChatSnapshot(known = known)

    /** Touched on [worker] only. */
    private var observation: UUID? = null
    private var hideTyping: (() -> Unit)? = null

    init {
        screen = ChatPresenter(ClomniStrings(language), timeZone, now()).screen(snapshot)
    }

    private val strings: ClomniStrings
        get() = ClomniStrings(language ?: snapshot.config?.languages?.firstOrNull(), snapshot.config?.strings.orEmpty())

    /** The cache at once, then the server; marks the conversation read. */
    fun load() {
        val id = conversationId
        worker.execute {
            publish(read(id))
            if (observation == null) observation = source.observe(::changed)
            if (source.conversation(id) == null) runCatching { source.refreshConversation(id).get() }
            val loaded = runCatching { source.loadMessages(id).get() }.isSuccess
            publish(read(id)) {
                snapshot = snapshot.copy(load = if (loaded) MessengerSnapshot.Load.LOADED else MessengerSnapshot.Load.FAILED)
            }
            source.markRead(id)
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
        worker.execute {
            runCatching { source.sendText(text, id).get() }
            source.setTyping(false, id)
        }
        return true
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
        worker.execute {
            runCatching { source.submitForm(message, FormInput.payload(form, values)).get() }
            publish(read(id))
        }
        return emptyMap()
    }

    /** "Göndərilmədi · Yenidən cəhd et". */
    fun retrySending(clientId: String) {
        worker.execute { runCatching { source.retry(clientId).get() } }
    }

    /**
     * An image (already scaled, see [Media.uploadSize]) or a file; [done] hears the text to show when it is refused,
     * or null.
     */
    fun sendFile(data: ByteArray, fileName: String, mime: String, caption: String? = null, done: (String?) -> Unit = {}) {
        val id = conversationId
        worker.execute {
            val failure = try {
                source.sendFile(data, fileName, mime, caption, id).get()
                null
            } catch (e: ExecutionException) {
                e.cause
            } catch (e: InterruptedException) {
                e
            }
            main.execute {
                val limits = snapshot.config?.limits
                done(
                    when {
                        failure == null -> null
                        failure is ClomniError.Rejected && failure.message.orEmpty().startsWith("file over") ->
                            strings.format(Key.FILE_TOO_LARGE, if (Media.isImage(mime)) limits?.imageMb ?: 10 else limits?.fileMb ?: 25)
                        else -> strings[Key.ERROR]
                    },
                )
            }
        }
    }

    /** "Yeni söhbət başlat": this screen moves to a new conversation; [done] hears its id, or null when it failed. */
    fun startNewConversation(done: (String?) -> Unit = {}) {
        val previous = conversationId
        worker.execute {
            val conversation = runCatching { source.startConversation(null).get() }.getOrNull()
            if (conversation != null) source.setTyping(false, previous)
            main.execute {
                if (conversation != null) {
                    hideTyping?.invoke()
                    hideTyping = null
                    conversationId = conversation.id
                    snapshot = ChatSnapshot(known = snapshot.known)
                    render()
                    load()
                }
                done(conversation?.id)
            }
        }
    }

    // The engine's changes (on its thread)

    private fun changed(change: ClomniChange) {
        val id = conversationId
        when (change) {
            is ClomniChange.Messages -> if (change.conversationId == id) {
                worker.execute {
                    val state = read(id)
                    publish(state) { before ->
                        // A message from whoever was typing ends the indicator.
                        val typing = snapshot.typing
                        val last = state.messages.lastOrNull()
                        if (typing != null && last != null && last.id != before.messages.lastOrNull()?.id &&
                            last.sender.type == typing.type
                        ) {
                            hideTyping?.invoke()
                            hideTyping = null
                            snapshot = snapshot.copy(typing = null)
                        }
                    }
                    source.markRead(id)
                }
            }
            is ClomniChange.Typing -> if (change.conversationId == id) {
                main.execute { showTyping(if (change.isTyping) change.sender else null) }
            }
            is ClomniChange.Read -> if (change.conversationId == id) worker.execute { publish(read(id)) }
            ClomniChange.Conversations, ClomniChange.Config, ClomniChange.Session -> worker.execute { publish(read(id)) }
            is ClomniChange.Unread -> Unit
        }
    }

    /** On [main]. */
    private fun showTyping(sender: Sender?) {
        hideTyping?.invoke()
        hideTyping = null
        snapshot = snapshot.copy(typing = sender)
        render()
        if (sender != null) hideTyping = scheduler.after(typingTimeoutMs) { showTyping(null) }
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
                snapshot = snapshot.copy(
                    config = state.config,
                    conversation = state.conversation,
                    messages = state.messages,
                    pending = state.pending,
                    readUpTo = state.readUpTo,
                    answerable = state.answerable,
                    localFiles = state.localFiles,
                )
                update(before)
                render()
            }
            after()
        }
    }

    private fun render() {
        snapshot = snapshot.copy(isOffline = isOffline)
        screen = ChatPresenter(strings, timeZone, now()).screen(snapshot)
        onChange?.invoke()
    }

    private companion object {
        /** The id [QuickReplyBlock.back] carries. */
        const val BACK = "back"
    }
}
