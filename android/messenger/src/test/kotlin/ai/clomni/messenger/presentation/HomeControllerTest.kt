package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.Future

/** A data source whose answers the test sets. */
private class FakeSource : MessengerDataSource {
    var cached: MessengerConfig? = null
    var fresh: MessengerConfig? = null
    var list = mutableListOf<Conversation>()
    var unread = 0
    var conversationsFail = false
    var startFails = false
    var starts = 0
    var handler: ((ClomniChange) -> Unit)? = null

    override val config: MessengerConfig? get() = cached
    override val unreadTotal: Int get() = unread

    override fun refreshConfig(language: String?): Future<MessengerConfig?> {
        if (fresh != null) cached = fresh
        return CompletableFuture.completedFuture(cached)
    }

    override fun conversations(): List<Conversation> = list.toList()

    override fun refreshConversations(): Future<Unit> =
        if (conversationsFail) CompletableFuture<Unit>().apply { completeExceptionally(ClomniError.Network("offline")) }
        else CompletableFuture.completedFuture(Unit)

    override fun startConversation(openedFrom: String?): Future<Conversation> {
        starts++
        if (startFails) return CompletableFuture<Conversation>().apply { completeExceptionally(ClomniError.Network("offline")) }
        val conversation = Fixture.conversation("conv_$starts", "09-apar-level1-A.json")
        list.add(0, conversation)
        return CompletableFuture.completedFuture(conversation)
    }

    override fun setChangeHandler(handler: (ClomniChange) -> Unit) {
        this.handler = handler
    }

    /** What the engine does when a socket event arrives. */
    fun push(unread: Int, change: ClomniChange) {
        this.unread = unread
        handler?.invoke(change)
    }
}

/** Work queued and run when the test says, so it can tap twice "at once". */
private class Queue : Executor {
    private val tasks = ArrayDeque<Runnable>()

    override fun execute(command: Runnable) {
        tasks.addLast(command)
    }

    fun drain() {
        while (tasks.isNotEmpty()) tasks.removeFirst().run()
    }
}

class HomeControllerTest {
    private val source = FakeSource()
    private val direct = Executor { it.run() }
    private var renders = 0

    private fun controller(user: String? = "Aysel", worker: Executor = direct, main: Executor = direct) =
        HomeController(source, "az", user, worker, main, TimeZone.getTimeZone("UTC")) { 1_790_850_720_000L }
            .also { it.onChange = { renders++ } }

    @Test
    fun startsAsASkeleton() {
        val home = controller()
        assertEquals(HomeScreen.Phase.LOADING, home.home.phase)
        assertEquals(HomeScreen.Phase.LOADING, home.messages.phase)
        assertEquals("Salam, Aysel 👋", home.home.header.greeting)
    }

    @Test
    fun showsTheCacheThenTheServersAnswer() {
        source.cached = Fixture.minimalConfig
        source.fresh = Fixture.aparConfig
        source.list += Fixture.conversation("conv_1", "02-text-operator-markdown.json")
        val home = controller()
        home.load()
        assertEquals("once from the cache, once after the refresh", 2, renders)
        assertEquals(HomeScreen.Phase.READY, home.home.phase)
        assertEquals("Apar", home.home.header.brandName)
        assertEquals("#1F9D63", home.config?.brand?.primaryColor)
        assertEquals("Leyla · 2 dəq", home.home.recent?.row?.detail)
        assertEquals(1, home.messages.rows.size)
    }

    @Test
    fun nothingCachedAndNoServerIsAnErrorWithRetry() {
        source.conversationsFail = true
        val home = controller()
        home.load()
        assertEquals(HomeScreen.Phase.FAILED, home.home.phase)
        assertEquals("Yenidən cəhd et", home.home.failure?.retry)
        assertEquals(HomeScreen.Phase.FAILED, home.messages.phase)

        source.fresh = Fixture.aparConfig
        source.conversationsFail = false
        home.retry()
        assertEquals(HomeScreen.Phase.READY, home.home.phase)
        assertEquals(HomeScreen.Phase.READY, home.messages.phase)
        assertEquals("Hələ söhbət yoxdur", home.messages.empty)
    }

    @Test
    fun engineChangesRedraw() {
        source.fresh = Fixture.aparConfig
        val home = controller()
        home.load()
        assertFalse(home.home.tabs.messagesUnread)
        val before = renders
        source.push(1, ClomniChange.Typing("conv_1", Sender(SenderType.OPERATOR), true))
        source.push(1, ClomniChange.Read("conv_1", 3))
        assertEquals("typing and read receipts are the conversation screen's business", before, renders)
        source.push(2, ClomniChange.Unread(2))
        assertTrue(home.home.tabs.messagesUnread)
        assertEquals(before + 1, renders)
    }

    @Test
    fun startingAConversation() {
        source.fresh = Fixture.aparConfig
        val main = Queue()
        val worker = Queue()
        val home = controller(worker = worker, main = main)
        home.load()
        worker.drain()
        main.drain()
        val ids = mutableListOf<String?>()
        home.startConversation("home") { ids += it }
        home.startConversation("home") { ids += it }
        // Both taps reach the UI thread before the first conversation exists.
        main.drain()
        worker.drain()
        main.drain()
        assertEquals("a second tap while the first is starting does nothing", listOf<String?>("conv_1"), ids)
        assertEquals(1, source.starts)
        assertEquals("conv_1", home.messages.rows.first().id)

        source.startFails = true
        home.startConversation(null) { ids += it }
        main.drain()
        worker.drain()
        main.drain()
        assertNull(ids.last())
    }

    @Test
    fun nameAndConnectivityRedraw() {
        val home = controller(user = null)
        assertEquals("Salam 👋", home.home.header.greeting)
        home.userName = "Leyla Əliyeva"
        assertEquals("Salam, Leyla 👋", home.home.header.greeting)
        home.isOffline = true
        assertEquals("İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq", home.home.offline)
        assertEquals(2, renders)
        assertEquals("Leyla Əliyeva", home.userName)
        assertTrue(home.isOffline)
    }
}
