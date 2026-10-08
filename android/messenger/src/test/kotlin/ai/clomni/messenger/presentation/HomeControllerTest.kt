package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.NewsItem
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone
import java.util.UUID
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
    var drafts = mutableListOf<String?>()
    var newsItems = listOf<NewsItem>()
    val opened = mutableListOf<String>()
    val observers = LinkedHashMap<UUID, (ClomniChange) -> Unit>()

    override val config: MessengerConfig? get() = cached
    override val unreadTotal: Int get() = unread

    override fun refreshConfig(language: String?): Future<MessengerConfig?> {
        if (fresh != null) cached = fresh
        return CompletableFuture.completedFuture(cached)
    }

    override fun conversations(): List<Conversation> = list.toList()

    override val news: List<NewsItem> get() = newsItems

    override fun refreshNews(language: String?): Future<List<NewsItem>> = CompletableFuture.completedFuture(newsItems)

    override fun newsOpened(id: String) {
        opened += id
    }

    override fun refreshConversations(): Future<Unit> =
        if (conversationsFail) CompletableFuture<Unit>().apply { completeExceptionally(ClomniError.Network("offline")) }
        else CompletableFuture.completedFuture(Unit)

    override fun draft(openedFrom: String?): String {
        drafts += openedFrom
        return "draft_${drafts.size}"
    }

    override fun observe(handler: (ClomniChange) -> Unit): UUID = UUID.randomUUID().also { observers[it] = handler }

    override fun stopObserving(token: UUID) {
        observers.remove(token)
    }

    /** What the engine does when a socket event arrives. */
    fun push(unread: Int, change: ClomniChange) {
        this.unread = unread
        observers.values.toList().forEach { it(change) }
    }
}

/** Work queued and run when the test says, so it can tap twice "at once". */
internal class Queue : Executor {
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

    /**
     * DESIGN-PASS-2 9: back on Home after the list or a conversation, its first frame is what the engine holds (the
     * panel's texts, the news), never the SDK's defaults until the cache is read.
     */
    @Test
    fun theFirstFrameIsWhatTheEngineHolds() {
        source.cached = Fixture.exampleConfig
        source.newsItems = listOf(NewsItem("news_1", "Yeni zonalar", "Qısa", null, null, null, null))
        val home = controller(worker = Queue())
        assertEquals("Bizdən nəsə soruşun", home.home.header.title)
        assertEquals(HomeScreen.Phase.READY, home.home.phase)
        assertEquals(listOf("news_1"), home.home.news.map { it.id })
        home.newsOpened("news_1")
        assertEquals(listOf("news_1"), source.opened)
        assertEquals("Yeni zonalar", home.newsScreen("news_1")?.title)
    }

    @Test
    fun startsAsASkeleton() {
        val home = controller()
        assertEquals(HomeScreen.Phase.LOADING, home.home.phase)
        assertEquals(HomeScreen.Phase.LOADING, home.messages.phase)
        assertEquals("Salam, Aysel", home.home.header.greeting)
    }

    @Test
    fun showsTheCacheThenTheServersAnswer() {
        source.cached = Fixture.minimalConfig
        source.fresh = Fixture.exampleConfig
        source.list += Fixture.conversation("conv_1", "02-text-operator-markdown.json")
        val home = controller()
        home.load()
        assertEquals("once from the cache, once after the refresh", 2, renders)
        assertEquals(HomeScreen.Phase.READY, home.home.phase)
        assertEquals("Example", home.home.header.brandName)
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

        source.fresh = Fixture.exampleConfig
        source.conversationsFail = false
        home.retry()
        assertEquals(HomeScreen.Phase.READY, home.home.phase)
        assertEquals(HomeScreen.Phase.READY, home.messages.phase)
        assertEquals("Hələ söhbət yoxdur", home.messages.empty)
    }

    @Test
    fun engineChangesRedraw() {
        source.fresh = Fixture.exampleConfig
        val home = controller()
        home.load()
        assertFalse(home.home.messagesCard.unread)
        val before = renders
        source.push(1, ClomniChange.Typing("conv_1", Sender(SenderType.OPERATOR), true))
        source.push(1, ClomniChange.Read("conv_1", 3))
        assertEquals("typing and read receipts are the conversation screen's business", before, renders)
        source.push(2, ClomniChange.Unread(2))
        assertTrue(home.home.messagesCard.unread)
        assertEquals(before + 1, renders)

        home.retry()
        assertEquals("loading again does not listen twice", 1, source.observers.size)
        home.stop()
        assertTrue(source.observers.isEmpty())
    }

    /** "Bizə mesaj göndərin" opens a draft: nothing goes to the server until its first message. */
    @Test
    fun startingAConversation() {
        val home = controller()
        home.load()
        assertEquals("draft_1", home.newConversation("home"))
        assertEquals("draft_2", home.newConversation(null))
        assertEquals(listOf<String?>("home", null), source.drafts)
        assertTrue("nothing in the list", home.messages.rows.isEmpty())
    }

    @Test
    fun nameAndConnectivityRedraw() {
        val home = controller(user = null)
        assertEquals("Salam", home.home.header.greeting)
        home.userName = "Leyla Əliyeva"
        assertEquals("Salam, Leyla", home.home.header.greeting)
        home.isOffline = true
        assertEquals("İnternet yoxdur", home.home.offline)
        assertEquals(2, renders)
        assertEquals("Leyla Əliyeva", home.userName)
        assertTrue(home.isOffline)
    }
}
