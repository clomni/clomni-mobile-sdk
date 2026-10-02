package ai.clomni.messenger.presentation

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.MessengerConfig
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Future

/** What the Home and Messages tabs read; `ClomniEngine` is one, tests use a fake. */
internal interface MessengerDataSource {
    val config: MessengerConfig?
    val unreadTotal: Int

    fun refreshConfig(language: String? = null): Future<MessengerConfig?>

    fun conversations(): List<Conversation>

    fun refreshConversations(): Future<Unit>

    /** A new conversation to write in; the server has it only once its first message goes (`ClomniChange.Started`). */
    fun draft(openedFrom: String?): String

    /** [handler] hears every change until [stopObserving] is called with the returned token. */
    fun observe(handler: (ClomniChange) -> Unit): UUID

    fun stopObserving(token: UUID)
}

/**
 * Keeps the Home and Messages screens current: what is cached at once, then the server's answer, then every change
 * the engine reports. The Compose views observe it through [onChange].
 *
 * The screens change only on [main] (the UI thread); waiting for the engine happens on [worker].
 */
internal class HomeController(
    private val source: MessengerDataSource,
    private val language: String?,
    userName: String?,
    private val worker: Executor,
    private val main: Executor,
    private val timeZone: TimeZone = TimeZone.getDefault(),
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var snapshot = MessengerSnapshot(userName = userName)

    /** Touched on [worker] only. */
    private var observation: UUID? = null

    var home: HomeScreen
        private set
    var messages: MessagesScreen
        private set

    /** Called on [main] after [home] or [messages] changed. */
    var onChange: (() -> Unit)? = null

    /** For the theme: the brand's colours and appearance. */
    val config: MessengerConfig? get() = snapshot.config

    var userName: String? = userName
        set(value) {
            field = value
            render()
        }

    /** The thin yellow strip; set from the device's connectivity. */
    var isOffline: Boolean = false
        set(value) {
            field = value
            render()
        }

    init {
        val presenter = HomePresenter(ClomniStrings(language), timeZone, now())
        home = presenter.home(snapshot)
        messages = presenter.messages(snapshot)
    }

    /** Shows the cache at once, then asks the server for the config and the conversations. */
    fun load() {
        worker.execute {
            publish(state())
            if (observation == null) observation = source.observe(::changed)
            val config = runCatching { source.refreshConfig(language).get() }.getOrNull()
            val conversations = runCatching { source.refreshConversations().get() }.isSuccess
            publish(state()) {
                snapshot = snapshot.copy(
                    configLoad = if (config != null) MessengerSnapshot.Load.LOADED else MessengerSnapshot.Load.FAILED,
                    conversationsLoad =
                        if (conversations) MessengerSnapshot.Load.LOADED else MessengerSnapshot.Load.FAILED,
                )
            }
        }
    }

    /** Stops following the engine's changes, when the messenger closes. */
    fun stop() {
        worker.execute {
            observation?.let(source::stopObserving)
            observation = null
        }
    }

    /** "Yenidən cəhd et". */
    fun retry() {
        main.execute {
            snapshot = snapshot.copy(
                configLoad = MessengerSnapshot.Load.LOADING,
                conversationsLoad = MessengerSnapshot.Load.LOADING,
            )
            render()
            load()
        }
    }

    /**
     * "Bizə mesaj göndərin": the id of a new conversation to open, which the server gets with its first message;
     * nothing is sent now (an opened and closed conversation leaves nothing in the panel).
     */
    fun newConversation(openedFrom: String?): String = source.draft(openedFrom)

    private fun changed(change: ClomniChange) {
        // Typing and read receipts are the conversation screen's business.
        if (change is ClomniChange.Typing || change is ClomniChange.Read) return
        worker.execute { publish(state()) }
    }

    /** What the engine holds now; read on [worker]. */
    private class State(val config: MessengerConfig?, val conversations: List<Conversation>, val unreadTotal: Int)

    private fun state() = State(source.config, source.conversations(), source.unreadTotal)

    /** Hands [state] to the UI thread, applies [update] there, redraws, then runs [after]. */
    private fun publish(state: State, after: () -> Unit = {}, update: () -> Unit = {}) {
        main.execute {
            snapshot = snapshot.copy(
                config = state.config,
                conversations = state.conversations,
                unreadTotal = state.unreadTotal,
            )
            update()
            render()
            after()
        }
    }

    private fun render() {
        snapshot = snapshot.copy(userName = userName, isOffline = isOffline)
        val config = snapshot.config
        val strings = ClomniStrings(language ?: config?.languages?.firstOrNull(), config?.strings.orEmpty())
        val presenter = HomePresenter(strings, timeZone, now())
        home = presenter.home(snapshot)
        messages = presenter.messages(snapshot)
        onChange?.invoke()
    }
}
