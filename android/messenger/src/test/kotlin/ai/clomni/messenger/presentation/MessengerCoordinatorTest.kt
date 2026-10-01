package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.Future

/** An SDK below the coordinator whose answers the test sets. */
private class FakeSession : MessengerSession {
    var loggedIn = false
    var disabled = false
    var disableOnLogin = false
    var loginFails = false
    var unread = 0
    var cachedConfig: MessengerConfig? = null
    var freshConfig: MessengerConfig? = Fixture.aparConfig
    var startFails = false
    var flowBound = true
    val stored = mutableMapOf<String, List<Message>>()
    val calls = mutableListOf<String>()
    val observers = LinkedHashMap<UUID, (ClomniChange) -> Unit>()

    override val isLoggedIn: Boolean get() = loggedIn
    override val isAppDisabled: Boolean get() = disabled
    override val unreadTotal: Int get() = unread
    override val config: MessengerConfig? get() = cachedConfig

    private fun <T> done(value: T): Future<T> = CompletableFuture.completedFuture(value)

    private fun <T> failed(error: Throwable): Future<T> = CompletableFuture<T>().apply { completeExceptionally(error) }

    override fun loginUnidentifiedUser(): Future<Unit> {
        calls += "login"
        if (disableOnLogin) {
            disabled = true
            return failed(ClomniError.Server(403, null))
        }
        if (loginFails) return failed(ClomniError.Network("offline"))
        loggedIn = true
        return done(Unit)
    }

    override fun refreshConfig(language: String?): Future<MessengerConfig?> {
        calls += "config"
        if (freshConfig != null) cachedConfig = freshConfig
        return done(cachedConfig)
    }

    override fun connect(): Future<Unit> {
        calls += "connect"
        return done(Unit)
    }

    override fun startConversation(openedFrom: String?): Future<Conversation> {
        calls += "start ${openedFrom ?: "-"}"
        return if (startFails) failed(ClomniError.Network("offline")) else done(ChatFixture.conversation("bot"))
    }

    override fun startFlow(event: String, data: JsonObject?, openMessenger: Boolean, openedFrom: String?): Future<Conversation?> {
        calls += "flow $event $openMessenger ${openedFrom ?: "-"} ${data ?: "{}"}"
        return done(if (flowBound) ChatFixture.conversation("bot") else null)
    }

    override fun messages(conversationId: String): List<Message> = stored[conversationId].orEmpty()

    override fun observe(handler: (ClomniChange) -> Unit): UUID = UUID.randomUUID().also { observers[it] = handler }

    override fun stopObserving(token: UUID) {
        observers.remove(token)
    }

    fun push(change: ClomniChange) = observers.values.toList().forEach { it(change) }
}

class MessengerCoordinatorTest {
    private val session = FakeSession()
    private val direct = Executor { it.run() }
    private val log = mutableListOf<String>()
    private val opened = mutableListOf<String?>()
    private var closed = 0
    private val started = mutableListOf<String>()
    private val unread = mutableListOf<Int>()
    private val flows = mutableListOf<String>()

    private fun coordinator(worker: Executor = direct, main: Executor = direct) =
        MessengerCoordinator(session, "az", worker, main) { log += it }.also { messenger ->
            messenger.events.messengerOpened = { opened += it }
            messenger.events.messengerClosed = { closed++ }
            messenger.events.conversationStarted = { started += it }
            messenger.events.unreadCountChanged = { unread += it }
            messenger.events.flowCompleted = { flows += it }
        }

    /** Brief 7.2, "Bitdi": with the launcher off, the app shows no Clomni element at all. */
    @Test
    fun nothingShowsUntilTheAppAsks() {
        session.loggedIn = true
        session.cachedConfig = Fixture.aparConfig
        val messenger = coordinator()
        assertFalse(messenger.wantsAnyView)
        messenger.start()
        assertEquals(MessengerCoordinator.Readiness.READY, messenger.readiness)
        assertNull("Apar's config has launcher.visible false", messenger.launcher)
        assertNull(messenger.route)
        assertFalse("no overlay, no activity, nothing", messenger.wantsAnyView)
        assertEquals(listOf("connect", "config"), session.calls)
    }

    @Test
    fun theLauncherRule() {
        val messenger = coordinator()
        messenger.setLauncherVisible(true)
        assertNull("not before the SDK is ready", messenger.launcher)
        session.loggedIn = true
        session.unread = 3
        messenger.start()
        assertEquals(
            LauncherState(MessengerConfig.LauncherPosition.RIGHT, 20, "3", "Bizə mesaj göndərin, Oxunmamış mesaj var"),
            messenger.launcher,
        )
        assertTrue(messenger.wantsAnyView)
        messenger.setBottomPadding(64)
        assertEquals(64, messenger.launcher?.bottomPadding)
        messenger.setBottomPadding(-5)
        assertEquals(0, messenger.launcher?.bottomPadding)
        messenger.present()
        assertNull("hidden while the messenger is open", messenger.launcher)
        messenger.dismiss()
        assertNotNull(messenger.launcher)
        messenger.setLauncherVisible(false)
        assertNull(messenger.launcher)
        assertFalse(messenger.wantsAnyView)

        // The panel can turn it on, on the left; the app's choice wins over the panel's.
        val panelOn = ProtocolJson().parseConfig(
            """{"brand":{"name":"Apar","primary_color":"#1F9D63"},"launcher":{"visible":true,"position":"left","bottom_padding":0}}""",
        )!!
        session.cachedConfig = panelOn
        session.freshConfig = panelOn
        session.unread = 120
        val fromPanel = coordinator()
        fromPanel.start()
        assertEquals(MessengerConfig.LauncherPosition.LEFT, fromPanel.launcher?.side)
        assertEquals(0, fromPanel.launcher?.bottomPadding)
        assertEquals("99+", fromPanel.launcher?.badge)
        fromPanel.setLauncherVisible(false)
        assertNull(fromPanel.launcher)
        session.unread = 0
        session.push(ClomniChange.Unread(0))
        fromPanel.setLauncherVisible(true)
        assertEquals("Bizə mesaj göndərin", fromPanel.launcher?.accessibilityLabel)
        assertNull(fromPanel.launcher?.badge)
    }

    @Test
    fun presentingAndDismissing() {
        val messenger = coordinator()
        assertTrue(messenger.present("profile_support"))
        assertEquals(MessengerRoute.Home, messenger.route)
        assertEquals("profile_support", messenger.source)
        assertTrue(messenger.wantsAnyView)
        // Opening a conversation while open is a move, not a second opening.
        messenger.presentConversation("conv_9", "push")
        assertEquals(MessengerRoute.Conversation("conv_9"), messenger.route)
        assertEquals("profile_support", messenger.source)
        messenger.navigate(MessengerRoute.Home)
        assertEquals(MessengerRoute.Home, messenger.route)
        messenger.dismiss()
        messenger.dismiss()
        messenger.navigate(MessengerRoute.Home)
        assertNull("navigating needs an open messenger", messenger.route)
        assertEquals(listOf<String?>("profile_support"), opened)
        assertEquals(1, closed)
        assertTrue(messenger.presentConversation("conv_9", "push"))
        assertEquals(listOf("profile_support", "push"), opened)
    }

    /** Opening before anyone logged in: an anonymous visitor, then the config, while the screens show skeletons. */
    @Test
    fun preparingLogsInAVisitorOnlyWhenNeeded() {
        val messenger = coordinator()
        messenger.present()
        val results = mutableListOf<Boolean>()
        messenger.prepare { results += it }
        assertEquals(MessengerCoordinator.Readiness.READY, messenger.readiness)
        assertEquals("Apar", messenger.config?.brand?.name)
        messenger.prepare { results += it }
        assertEquals(listOf(true, true), results)
        assertEquals(listOf("login", "connect", "config", "connect", "config"), session.calls)
    }

    /** No network at all: the open messenger stays (never an empty screen) and offers to try again. */
    @Test
    fun preparingWithoutNetwork() {
        session.loginFails = true
        val messenger = coordinator()
        messenger.present()
        val results = mutableListOf<Boolean>()
        messenger.prepare { results += it }
        assertEquals(listOf(false), results)
        assertTrue(messenger.prepareFailed)
        assertEquals(MessengerRoute.Home, messenger.route)
        assertEquals(MessengerCoordinator.Readiness.NOT_READY, messenger.readiness)
        assertTrue(log.single().startsWith("the messenger cannot open"))
        session.loginFails = false
        messenger.prepare { results += it }
        assertFalse(messenger.prepareFailed)
        assertEquals(listOf(false, true), results)
    }

    /** 403 app_disabled: present() does nothing and says so in the log. */
    @Test
    fun aSwitchedOffInboxOpensNothing() {
        session.disableOnLogin = true
        val messenger = coordinator()
        messenger.setLauncherVisible(true)
        assertTrue("not known yet", messenger.present())
        val results = mutableListOf<Boolean>()
        messenger.prepare { results += it }
        assertEquals(listOf(false), results)
        assertEquals(MessengerCoordinator.Readiness.DISABLED, messenger.readiness)
        assertNull("the half-open messenger closes", messenger.route)
        assertFalse(messenger.present())
        assertNull(messenger.route)
        assertNull(messenger.launcher)
        assertFalse(messenger.wantsAnyView)
        val ids = mutableListOf<String?>()
        messenger.presentNewConversation { ids += it }
        messenger.startFlow("payment_failed", null, openMessenger = true) { ids += it }
        messenger.prepare { results += it }
        assertEquals(listOf<String?>(null, null), ids)
        assertEquals(listOf(false, false), results)
        assertTrue(log.any { it.contains("switched off in Clomni: present() does nothing") })

        val known = FakeSession().apply {
            loggedIn = true
            disabled = true
        }
        val coordinator = MessengerCoordinator(known, "az", direct, direct)
        coordinator.start()
        assertEquals(MessengerCoordinator.Readiness.DISABLED, coordinator.readiness)
        assertFalse(coordinator.present())
    }

    @Test
    fun aNewConversationCarriesTheSource() {
        session.loggedIn = true
        val messenger = coordinator()
        val ids = mutableListOf<String?>()
        messenger.presentNewConversation("ride_screen") { ids += it }
        assertEquals(listOf<String?>("conv_5521"), ids)
        assertEquals(MessengerRoute.Conversation("conv_5521"), messenger.route)
        assertEquals(listOf("conv_5521"), started)
        assertEquals(listOf<String?>("ride_screen"), opened)
        assertTrue(session.calls.toString(), "start ride_screen" in session.calls)

        messenger.dismiss()
        session.startFails = true
        messenger.presentNewConversation { ids += it }
        assertNull(ids.last())
        assertEquals("Home, with its retry, instead of an endless skeleton", MessengerRoute.Home, messenger.route)
        assertTrue("start -" in session.calls)
        messenger.conversationStarted("conv_from_home")
        assertEquals(listOf("conv_5521", "conv_from_home"), started)

        // Closed while it was starting: it stays closed.
        messenger.dismiss()
        session.startFails = false
        val worker = Queue()
        val slow = coordinator(worker = worker)
        slow.presentNewConversation { ids += it }
        assertEquals(MessengerRoute.StartingConversation, slow.route)
        slow.dismiss()
        worker.drain()
        assertNull(slow.route)
        assertEquals("conv_5521", ids.last())
    }

    @Test
    fun startingAFlow() {
        session.loggedIn = true
        val messenger = coordinator()
        val ids = mutableListOf<String?>()
        val data = JsonObject(mapOf("order_id" to JsonPrimitive("A-1042")))
        messenger.startFlow("payment_failed", data, openMessenger = false) { ids += it }
        assertNull("open_messenger false: only a push or the badge will tell", messenger.route)
        messenger.startFlow("ride_problem", null, openMessenger = true, source = "ride_screen") { ids += it }
        assertEquals(MessengerRoute.Conversation("conv_5521"), messenger.route)
        assertEquals(listOf<String?>("ride_screen"), opened)
        assertEquals(listOf<String?>("conv_5521", "conv_5521"), ids)
        assertEquals(listOf("conv_5521", "conv_5521"), started)
        assertEquals(
            listOf("""flow payment_failed false - {"order_id":"A-1042"}""", "flow ride_problem true ride_screen {}"),
            session.calls.filter { it.startsWith("flow") },
        )
        session.flowBound = false
        messenger.startFlow("nothing_bound", null, openMessenger = true) { ids += it }
        assertNull(ids.last())
    }

    @Test
    fun unreadCount() {
        session.loggedIn = true
        session.unread = 2
        val messenger = coordinator()
        val counts = mutableListOf<Int>()
        val token = messenger.addUnreadCountListener { counts += it }
        assertEquals("called at once", listOf(0), counts)
        messenger.start()
        session.push(ClomniChange.Unread(5))
        assertEquals(listOf(0, 2, 5), counts)
        assertEquals(listOf(2, 5), unread)
        messenger.removeUnreadCountListener(token)
        session.push(ClomniChange.Unread(0))
        assertEquals(listOf(0, 2, 5), counts)
        assertEquals(listOf(2, 5, 0), unread)
        assertEquals(0, messenger.unreadTotal)
        messenger.start()
        assertEquals("listens once", 1, session.observers.size)
    }

    /** A message from a flow's END node completes the flow; ENDs already there when first seen are history. */
    @Test
    fun flowCompleted() {
        session.loggedIn = true
        val messenger = coordinator()
        messenger.start()
        val old = ChatFixture.message("50-apar-end.json", "id" to "msg_old_end")
        session.stored["conv_5521"] = listOf(old)
        session.push(ClomniChange.Messages("conv_5521"))
        assertTrue(flows.isEmpty())
        val step = ChatFixture.message("12-apar-level4-handoff.json")
        val end = ChatFixture.message("50-apar-end.json")
        session.stored["conv_5521"] = listOf(old, step, end)
        session.push(ClomniChange.Messages("conv_5521"))
        session.push(ClomniChange.Messages("conv_5521"))
        assertEquals(listOf("flw_apar_az"), flows)
        session.cachedConfig = Fixture.minimalConfig
        session.push(ClomniChange.Config)
        assertEquals("Clomni, Inc.", messenger.config?.brand?.name)
        session.push(ClomniChange.Session)
    }

    @Test
    fun loggingOutHidesEverything() {
        session.loggedIn = true
        session.unread = 4
        val messenger = coordinator()
        messenger.setLauncherVisible(true)
        messenger.start()
        messenger.present()
        messenger.loggedOut()
        assertNull(messenger.route)
        assertEquals(MessengerCoordinator.Readiness.NOT_READY, messenger.readiness)
        assertEquals(0, messenger.unreadTotal)
        assertEquals(listOf(4, 0), unread)
        assertEquals(1, closed)
        assertFalse(messenger.wantsAnyView)
    }

    @Test
    fun theEngineIsAMessengerSession() {
        val session: MessengerSession? = null as ai.clomni.messenger.core.ClomniEngine?
        assertNull(session)
    }
}
