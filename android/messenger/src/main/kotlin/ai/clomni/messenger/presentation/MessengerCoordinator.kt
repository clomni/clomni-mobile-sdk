package ai.clomni.messenger.presentation

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.PushPayload
import kotlinx.serialization.json.JsonObject
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Future

/** What opening the messenger needs from the SDK below; `ClomniEngine` is one, tests use a fake. */
internal interface MessengerSession {
    val isLoggedIn: Boolean
    val isAppDisabled: Boolean
    val unreadTotal: Int
    val config: MessengerConfig?

    /** [config], read from the disk cache now if need be (a small file). */
    fun cachedConfig(): MessengerConfig?

    fun loginUnidentifiedUser(): Future<Unit>

    fun refreshConfig(language: String?): Future<MessengerConfig?>

    fun connect(): Future<Unit>

    /** A new conversation to write in; the server has it only once its first message goes (`ClomniChange.Started`). */
    fun draft(openedFrom: String?): String

    fun startFlow(event: String, data: JsonObject?, openMessenger: Boolean, openedFrom: String?): Future<Conversation?>

    fun messages(conversationId: String): List<Message>

    fun observe(handler: (ClomniChange) -> Unit): UUID

    fun stopObserving(token: UUID)
}

/** Where the open messenger is. */
internal sealed interface MessengerRoute {
    data object Home : MessengerRoute

    /** The list of conversations, opened from Home's "Mesajlar" card. */
    data object Messages : MessengerRoute

    /** A news item's own screen. */
    data class News(val id: String) : MessengerRoute

    /** A conversation, or a new one not yet on the server ([MessengerSession.draft]). */
    data class Conversation(val id: String) : MessengerRoute
}

/** The optional floating button (brief 8·7.2): off unless the app or the panel turns it on. */
internal data class LauncherState(
    val side: MessengerConfig.LauncherPosition,
    /** Above the bottom edge, for a bottom navigation bar (`setBottomPadding`), dp. */
    val bottomPadding: Int,
    /** The unread count on the button: "3", "99+"; null when nothing is unread. */
    val badge: String?,
    val accessibilityLabel: String,
) {
    companion object {
        const val SIZE = 56

        /** From the screen's side and bottom edges, dp. */
        const val EDGE_PADDING = 20
    }
}

/** The app's callbacks (brief 8·9). */
internal class MessengerEvents {
    // Set from any thread, called on the UI thread.

    /** With the `source` the app passed to `present`. */
    @Volatile var messengerOpened: ((String?) -> Unit)? = null

    @Volatile var messengerClosed: (() -> Unit)? = null

    @Volatile var conversationStarted: ((String) -> Unit)? = null

    @Volatile var unreadCountChanged: ((Int) -> Unit)? = null

    /** `Clomni.onLink`: a news button's link; true when the app opened it, otherwise the system does. */
    @Volatile var link: ((String) -> Boolean)? = null

    /** A flow reached its END node, with the flow's id. */
    @Volatile var flowCompleted: ((String) -> Unit)? = null
}

/**
 * Opening and closing the messenger, the unread count and the launcher's rule, without any UI: the Android layer
 * starts the messenger's activity while [route] is set and draws the launcher while [launcher] is, nothing else. With
 * the launcher off and the messenger closed, [wantsAnyView] is false: the app shows no Clomni element (brief 7.2).
 * The same rules as the iOS SDK's MessengerCoordinator.
 *
 * Its state changes only on [main] (the UI thread); waiting for the SDK happens on [worker].
 */
internal class MessengerCoordinator(
    private val session: MessengerSession,
    private val language: String?,
    private val worker: Executor,
    private val main: Executor,
    private val log: (String) -> Unit = {},
    /** The app's callbacks; the runtime keeps them, so callbacks set before `initialize` are not lost. */
    val events: MessengerEvents = MessengerEvents(),
) {
    enum class Readiness {
        NOT_READY,
        READY,

        /** The App SDK inbox is switched off (403 app_disabled): nothing opens, no launcher. */
        DISABLED,
    }

    var readiness: Readiness = Readiness.NOT_READY
        private set

    /** Null while the messenger is closed. Read by push handling on FCM's thread too. */
    @Volatile
    var route: MessengerRoute? = null
        private set

    /** The `source` of the open messenger, written to a new conversation's `opened_from`. */
    var source: String? = null
        private set

    /** The last attempt to get ready reached nothing (no network): the open messenger offers to try again. */
    var prepareFailed: Boolean = false
        private set

    var unreadTotal: Int = 0
        private set

    var config: MessengerConfig? = null
        private set

    /** Called on [main] after the route, readiness, unread count or launcher changed. */
    var onChange: (() -> Unit)? = null

    private var launcherOverride: Boolean? = null
    private var bottomPaddingOverride: Int? = null
    private val listeners = LinkedHashMap<UUID, (Int) -> Unit>()

    /** Touched on [worker] only. */
    private var observation: UUID? = null

    /** END messages already seen, per conversation; a conversation's first look reports none (they are history). */
    private val finished = HashMap<String, Set<String>>()

    private val strings: ClomniStrings
        get() = ClomniStrings(language ?: config?.languages?.firstOrNull(), config?.strings.orEmpty())

    /** Whether the app should hold any Clomni view: only while the messenger is open or the launcher shows. */
    val wantsAnyView: Boolean get() = route != null || launcher != null

    /**
     * Present only when turned on (`setLauncherVisible`, else the config's `launcher.visible`), the SDK is ready and
     * the messenger is closed.
     */
    val launcher: LauncherState?
        get() {
            if (readiness != Readiness.READY || route != null) return null
            if (!(launcherOverride ?: config?.theme?.launcher?.enabled ?: false)) return null
            val badge = when {
                unreadTotal > 99 -> "99+"
                unreadTotal > 0 -> unreadTotal.toString()
                else -> null
            }
            val label = strings[ClomniStrings.Key.SEND_CARD_TITLE] +
                if (unreadTotal > 0) ", ${strings[ClomniStrings.Key.UNREAD_MESSAGES]}" else ""
            return LauncherState(
                side = config?.theme?.launcher?.position ?: MessengerConfig.LauncherPosition.RIGHT,
                bottomPadding = bottomPaddingOverride ?: config?.theme?.launcher?.bottomPadding ?: 20,
                badge = badge,
                accessibilityLabel = label,
            )
        }

    // Getting ready

    /**
     * Before the messenger's first frame (on the UI thread): the look the previous run kept, read now if the SDK's
     * worker has not yet, so the screen opens in the brand's colours instead of changing to them.
     */
    fun firstFrame() {
        if (config != null) return
        config = session.cachedConfig() ?: return
        changed()
    }

    /** After initialize and login: listens to the SDK, takes the cached config and unread count, opens the socket. */
    fun start(done: () -> Unit = {}) {
        worker.execute {
            listen()
            val cached = session.config
            val unread = session.unreadTotal
            if (session.isLoggedIn) openOnCache(cached, unread)
            var fresh: MessengerConfig? = null
            val state = when {
                session.isAppDisabled -> Readiness.DISABLED
                session.isLoggedIn -> {
                    runCatching { session.connect().get() }
                    fresh = runCatching { session.refreshConfig(language).get() }.getOrNull()
                    if (session.isAppDisabled) Readiness.DISABLED else Readiness.READY
                }
                else -> null
            }
            main.execute {
                config = fresh ?: cached ?: config
                updateUnread(unread)
                if (state != null) readiness = state
                if (state == Readiness.DISABLED) route = null
                changed()
                done()
            }
        }
    }

    /**
     * A session (an anonymous visitor when the app has logged nobody in) and the config: what an open messenger needs.
     * While this runs the screens show skeletons. [done] hears false when the inbox is switched off or nothing could
     * be reached.
     */
    fun prepare(done: (Boolean) -> Unit = {}) {
        main.execute {
            if (readiness == Readiness.DISABLED) return@execute done(false)
            prepareFailed = false
            changed()
            worker.execute {
                listen()
                var failure: String? = null
                if (session.isLoggedIn) openOnCache(session.config, session.unreadTotal)
                if (!session.isLoggedIn) {
                    failure = runCatching { session.loginUnidentifiedUser().get() }.exceptionOrNull()
                        ?.let { "the messenger cannot open: ${it.cause ?: it}" }
                }
                var fresh: MessengerConfig? = null
                if (failure == null && !session.isAppDisabled) {
                    runCatching { session.connect().get() }
                    fresh = runCatching { session.refreshConfig(language).get() }.getOrNull()
                }
                val disabled = session.isAppDisabled
                val unread = session.unreadTotal
                main.execute {
                    when {
                        disabled -> refuse(disabled = true, null)
                        failure != null -> refuse(disabled = false, failure)
                        else -> {
                            config = fresh ?: config
                            readiness = Readiness.READY
                            updateUnread(unread)
                            changed()
                        }
                    }
                    done(!disabled && failure == null)
                }
            }
        }
    }

    /**
     * On the worker: logged in with a kept look, the messenger is ready now, on the cache (DESIGN-PASS-3 C1, C2); the
     * socket and the config's ETag check follow, and a changed config redraws the screens when it comes. Offline, or
     * on a slow network, the user sees what they saw last time instead of skeletons.
     */
    private fun openOnCache(cached: MessengerConfig?, unread: Int) {
        if (cached == null || session.isAppDisabled) return
        main.execute {
            if (readiness != Readiness.NOT_READY) return@execute
            config = config ?: cached
            readiness = Readiness.READY
            updateUnread(unread)
            changed()
        }
    }

    private fun refuse(disabled: Boolean, reason: String?) {
        if (disabled) {
            readiness = Readiness.DISABLED
            route = null
            source = null
            log("this App SDK inbox is switched off in Clomni: the messenger does not open")
        } else {
            prepareFailed = true
            reason?.let(log)
        }
        changed()
    }

    /** After `logout`: the messenger closes, the count goes to 0, and nothing shows until the next login. */
    fun loggedOut() {
        dismiss()
        if (readiness == Readiness.READY) readiness = Readiness.NOT_READY
        updateUnread(0)
        finished.clear()
        changed()
    }

    // Opening and closing (on the UI thread)

    /** Home. False (and nothing opens) when the inbox is switched off. */
    fun present(source: String? = null): Boolean = open(MessengerRoute.Home, source)

    /** One conversation; from a push, [source] is "push". */
    fun presentConversation(id: String, source: String? = null): Boolean = open(MessengerRoute.Conversation(id), source)

    /**
     * A new, empty conversation on screen; the server gets it with the user's first message, and the app's
     * onConversationStarted hears it then. Opening and closing it sends nothing. [done] hears the draft's id, or null
     * when the inbox is switched off.
     */
    fun presentNewConversation(source: String? = null, done: (String?) -> Unit = {}) {
        val draft = session.draft(source)
        if (!open(MessengerRoute.Conversation(draft), source)) return done(null)
        done(draft)
    }

    /** `Clomni.startFlow`: the flow bound to an app event, in a new conversation, shown when [openMessenger]. */
    fun startFlow(event: String, data: JsonObject?, openMessenger: Boolean, source: String? = null, done: (String?) -> Unit = {}) {
        prepare { ready ->
            if (!ready) return@prepare done(null)
            worker.execute {
                val conversation = runCatching { session.startFlow(event, data, openMessenger, source).get() }
                    .onFailure { log("startFlow($event): ${it.cause ?: it}") }
                    .getOrNull()
                main.execute {
                    if (conversation != null) {
                        conversationStarted(conversation.id)
                        if (openMessenger) open(MessengerRoute.Conversation(conversation.id), source)
                    }
                    done(conversation?.id)
                }
            }
        }
    }

    /** Where back leads, the last first; empty: back closes the messenger. */
    private val backStack = ArrayDeque<MessengerRoute>()

    /** The last move went deeper (a push) rather than back (a pop): which way the screens slide. */
    var forward = true
        private set

    /** A move deeper inside the open messenger: the list, a conversation; back returns to where it came from. */
    fun navigate(to: MessengerRoute) {
        val from = route ?: return
        if (from == to) return
        backStack.addLast(from)
        forward = true
        route = to
        changed()
    }

    /** Back (the arrow, the system's back): the screen it came from, or closed from the first one. */
    fun back() {
        if (route == null) return
        val previous = backStack.removeLastOrNull() ?: return dismiss()
        forward = false
        route = previous
        changed()
    }

    /** `Clomni.dismiss()`, or the user closing it; the app returns to where it was. */
    fun dismiss() {
        if (route == null) return
        route = null
        backStack.clear()
        source = null
        events.messengerClosed?.invoke()
        changed()
    }

    /** A conversation the user started (from Home, or "Yeni söhbət başlat"). */
    fun conversationStarted(id: String) {
        events.conversationStarted?.invoke(id)
    }

    /** Conversations that began as a draft, by their id: the draft's screen stays the same screen. */
    private val drafts = HashMap<String, String>()

    /** The screen showing conversation [id]: its draft's, when it began as one. */
    fun screenKey(id: String): String = drafts[id] ?: id

    /** A draft's first message created its conversation: the screen showing the draft now shows it. */
    private fun started(draftId: String, conversationId: String) {
        drafts[conversationId] = draftId
        if (route == MessengerRoute.Conversation(draftId)) route = MessengerRoute.Conversation(conversationId)
        conversationStarted(conversationId)
        changed()
    }

    private fun open(to: MessengerRoute, source: String?): Boolean {
        if (readiness == Readiness.DISABLED) {
            log("this App SDK inbox is switched off in Clomni: present() does nothing")
            return false
        }
        val wasClosed = route == null
        val from = route
        forward = true
        if (wasClosed) {
            // A conversation opened from the app (or a push) goes back to Home, as one opened there does.
            backStack.clear()
            if (to !is MessengerRoute.Home) backStack.addLast(MessengerRoute.Home)
        } else if (from != null && from != to) {
            backStack.addLast(from)
        }
        route = to
        if (wasClosed) {
            this.source = source
            events.messengerOpened?.invoke(source)
        }
        changed()
        return true
    }

    // Push

    /**
     * A Clomni push arrived (FCM, on its own thread): its unread count reaches the listeners, and it is shown only
     * while the messenger is closed. Open on any screen, it shows the conversation's news itself.
     */
    fun received(push: PushPayload?): Boolean {
        push?.unreadTotal?.let { total -> main.execute { takeUnread(total) } }
        return route == null
    }

    /**
     * A tap on a Clomni notification: its conversation ("push" opened it), or Home for one this SDK could not read.
     * The count came with the push already.
     */
    fun openFromPush(conversationId: String?): Boolean =
        if (conversationId != null) presentConversation(conversationId, "push") else present("push")

    /** The server's count when it sent the push; the socket's next count replaces it. */
    private fun takeUnread(total: Int) {
        if (total == unreadTotal) return
        updateUnread(total)
        changed()
    }

    // Launcher

    fun setLauncherVisible(visible: Boolean) {
        launcherOverride = visible
        changed()
    }

    /** Lifts the launcher above a bottom navigation bar, dp. */
    fun setBottomPadding(padding: Int) {
        bottomPaddingOverride = maxOf(0, padding)
        changed()
    }

    // Unread count

    /** Called at once with the current count, then with every change, until removed. */
    fun addUnreadCountListener(listener: (Int) -> Unit): UUID {
        val token = UUID.randomUUID()
        listeners[token] = listener
        listener(unreadTotal)
        return token
    }

    fun removeUnreadCountListener(token: UUID) {
        listeners.remove(token)
    }

    private fun updateUnread(total: Int) {
        if (total == unreadTotal) return
        unreadTotal = total
        listeners.values.toList().forEach { it(total) }
        events.unreadCountChanged?.invoke(total)
    }

    // The SDK's changes (on its thread)

    /** On [worker]. */
    private fun listen() {
        if (observation == null) observation = session.observe(::changed)
    }

    private fun changed(change: ClomniChange) {
        when (change) {
            is ClomniChange.Unread -> main.execute {
                updateUnread(change.total)
                changed()
            }
            ClomniChange.Config -> worker.execute {
                val fresh = session.config
                main.execute {
                    config = fresh
                    changed()
                }
            }
            is ClomniChange.Started -> main.execute { started(change.draftId, change.conversationId) }
            is ClomniChange.Messages -> worker.execute {
                val messages = session.messages(change.conversationId)
                main.execute { reportFinishedFlows(change.conversationId, messages) }
            }
            else -> Unit
        }
    }

    /**
     * A message from the END node means its flow is complete (the server's convention, fixture 50) until the server
     * sends `flow.completed` itself.
     */
    private fun reportFinishedFlows(conversationId: String, messages: List<Message>) {
        val ends = messages.filter { it.flow?.nodeId == "END" }
        val seen = finished[conversationId]
        finished[conversationId] = seen.orEmpty() + ends.map { it.id }
        if (seen == null) return
        for (message in ends) {
            if (message.id !in seen) message.flow?.flowId?.let { events.flowCompleted?.invoke(it) }
        }
    }

    private fun changed() {
        onChange?.invoke()
    }
}
