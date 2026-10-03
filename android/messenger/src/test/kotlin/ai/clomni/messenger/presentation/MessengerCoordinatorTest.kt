package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.PushPayload
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

    /** What the disk cache holds before the worker has read it. */
    var diskConfig: MessengerConfig? = null

    override fun cachedConfig(): MessengerConfig? = cachedConfig ?: diskConfig
    var freshConfig: MessengerConfig? = Fixture.aparConfig
    var drafts = 0
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

    override fun draft(openedFrom: String?): String {
        calls += "draft ${openedFrom ?: "-"}"
        return "draft_${++drafts}"
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
        MessengerCoordinator(session, "az", worker, main, log = { log += it }).also { messenger ->
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
            """{"brand":{"name":"Apar","primary_color":"#1F9D63"},"theme":{"launcher":{"enabled":true,"position":"left","bottom_padding":0}}}""",
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

    /** Brief: no empty conversations. A new one is a draft on screen until its first message creates it. */
    @Test
    fun aNewConversationIsADraftUntilItsFirstMessage() {
        session.loggedIn = true
        val messenger = coordinator()
        messenger.start()
        val ids = mutableListOf<String?>()
        messenger.presentNewConversation("ride_screen") { ids += it }
        assertEquals(listOf<String?>("draft_1"), ids)
        assertEquals(MessengerRoute.Conversation("draft_1"), messenger.route)
        assertEquals(listOf<String?>("ride_screen"), opened)
        assertTrue(session.calls.toString(), "draft ride_screen" in session.calls)
        assertEquals("nothing started yet", emptyList<String>(), started)

        // The first message created it: the screen follows it there, and the app hears of it.
        session.push(ClomniChange.Started("draft_1", "conv_5521"))
        assertEquals(MessengerRoute.Conversation("conv_5521"), messenger.route)
        assertEquals(listOf("conv_5521"), started)

        // Opened and closed without a word: nothing reached the server, nothing reaches the app.
        messenger.dismiss()
        messenger.presentNewConversation { ids += it }
        messenger.dismiss()
        assertEquals(listOf("conv_5521"), started)
        // A draft created after the screen moved on is still the app's news.
        session.push(ClomniChange.Started("draft_2", "conv_6000"))
        assertNull(messenger.route)
        assertEquals(listOf("conv_5521", "conv_6000"), started)
    }

    /** The messenger's first frame has the look the previous run kept, not a default that changes to it. */
    @Test
    fun theFirstFrameHasTheCachedLook() {
        val blue = ChatFixture.config("""{"brand":{"name":"A","primary_color":"#0A66C2"}}""")
        session.diskConfig = blue
        val messenger = coordinator()
        assertNull(messenger.config)
        var changes = 0
        messenger.onChange = { changes++ }
        messenger.firstFrame()
        assertEquals(blue, messenger.config)
        assertEquals(1, changes)
        messenger.firstFrame()
        assertEquals("read once", 1, changes)
    }

    /** DESIGN-PASS-2 1, 8: Home → the list → a conversation; back retraces them, and from Home it closes. */
    @Test
    fun backRetracesTheWay() {
        session.loggedIn = true
        val messenger = coordinator()
        messenger.present()
        messenger.navigate(MessengerRoute.Messages)
        assertTrue(messenger.forward)
        messenger.navigate(MessengerRoute.Conversation("conv_1"))
        messenger.back()
        assertEquals(MessengerRoute.Messages, messenger.route)
        assertFalse("back slides the other way", messenger.forward)
        messenger.back()
        assertEquals(MessengerRoute.Home, messenger.route)
        messenger.back()
        assertNull("from Home, back closes", messenger.route)
        // Opened straight into a conversation (the app, a push): back goes to Home.
        messenger.presentConversation("conv_2")
        messenger.back()
        assertEquals(MessengerRoute.Home, messenger.route)
        // A news item, from Home.
        messenger.navigate(MessengerRoute.News("news_12"))
        messenger.back()
        assertEquals(MessengerRoute.Home, messenger.route)
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

    // Push

    private fun push(conversation: String = "conv_5521", unread: Int? = 2) = PushPayload(
        "message", conversation, "msg_f02", "Leyla · Apar", "Balansınıza 2 AZN qaytarıldı.", "https://app.clomni.ai/a/leyla.png", unread,
    )

    @Test
    fun aTapOnAPushOpensItsConversation() {
        session.loggedIn = true
        val messenger = coordinator()
        messenger.start()
        val counts = mutableListOf<Int>()
        messenger.addUnreadCountListener { counts += it }
        assertTrue(messenger.received(push()))
        assertTrue(messenger.openFromPush("conv_5521"))
        assertEquals(MessengerRoute.Conversation("conv_5521"), messenger.route)
        assertEquals("push", messenger.source)
        assertEquals(listOf<String?>("push"), opened)
        assertEquals(listOf(0, 2), counts)
        assertEquals(listOf(2), unread)

        // Already open: the messenger moves to the push's conversation, still opened once.
        messenger.navigate(MessengerRoute.Home)
        messenger.received(push("conv_7", unread = null))
        assertTrue(messenger.openFromPush("conv_7"))
        assertEquals(MessengerRoute.Conversation("conv_7"), messenger.route)
        assertEquals(listOf<String?>("push"), opened)
        assertEquals("no count in the push, no change", listOf(0, 2), counts)

        // One this SDK could not read opens Home.
        messenger.dismiss()
        assertTrue(messenger.openFromPush(null))
        assertEquals(MessengerRoute.Home, messenger.route)
    }

    /** A Clomni push shows only while the messenger is closed; open on any screen, it is held back. */
    @Test
    fun aPushShowsOnlyWhileTheMessengerIsClosed() {
        session.loggedIn = true
        val messenger = coordinator()
        messenger.start()
        assertTrue("closed", messenger.received(push(unread = 3)))
        assertEquals("the count reaches the app either way", listOf(3), unread)
        messenger.present()
        assertFalse("Home", messenger.received(push(unread = 4)))
        messenger.navigate(MessengerRoute.Conversation("conv_7"))
        assertFalse("another conversation", messenger.received(push(unread = 4)))
        messenger.dismiss()
        assertTrue(messenger.received(null))
        assertEquals(listOf(3, 4), unread)
    }

    @Test
    fun aSwitchedOffInboxOpensNothingFromAPush() {
        session.loggedIn = true
        session.disabled = true
        val messenger = coordinator()
        messenger.start()
        assertFalse(messenger.openFromPush("conv_5521"))
        assertNull(messenger.route)
        assertTrue(opened.isEmpty())
    }

    @Test
    fun theEngineIsAMessengerSession() {
        val session: MessengerSession? = null as ai.clomni.messenger.core.ClomniEngine?
        assertNull(session)
    }
}
