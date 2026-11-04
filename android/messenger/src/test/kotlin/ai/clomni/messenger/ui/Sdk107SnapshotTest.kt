package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ChatFixture
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.presentation.MessengerTab
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.FaqItem
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.MessengerConfig.HomeCard as Card
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import kotlinx.serialization.json.JsonNull
import org.junit.Rule
import org.junit.Test
import java.util.TimeZone

/**
 * SDK 1.0.7 (CM-341) as Paparazzi draws it: the tab bar, Home's news with "Hamısı" and its FAQ card, the questions'
 * list and search, a deleted message, «Sil» in the menu and its question.
 */
class Sdk107SnapshotTest {
    private val semantics = SemanticsCapture()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderExtensions = setOf(semantics),
    )

    /** 2026-10-01T10:32Z: two minutes after the fixtures' messages. */
    private val now = 1_790_850_720_000L

    private val news = ProtocolJson().parseNews(ProtocolFiles.read("fixtures/61-news.json"))!!

    private val faq = listOf(
        FaqItem("faq_1", "Balansı necə artırım?", "Balansı **kartla** və ya terminalla artırmaq olar.\n\n- Kart: dərhal\n- Terminal: 5 dəqiqəyə", null),
        FaqItem("faq_2", "Gediş bitmədisə nə edim?", "Tətbiqdə «Gedişi bitir» düyməsinə basın, sonra bizə yazın.", null),
        FaqItem("faq_3", "Kartı necə silim?", "Profil › Ödəniş üsulları bölməsində kartı sola sürüşdürün.", null),
        FaqItem("faq_4", "Velosipedi harada saxlaya bilərəm?", "Xəritədə yaşıl zonalarda.", null),
    )

    private val leyla: Conversation = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)

    /** The example config with the panel's tab bar, the FAQ on and its card after the news. */
    private val config: MessengerConfig = Fixture.exampleConfig.let {
        it.copy(
            home = it.home.copy(
                tabBar = true,
                cards = listOf(Card.MESSAGES, Card.RECENT, Card.SEND, Card.NEWS, Card.FAQ, Card.CHANNELS),
            ),
            faqEnabled = true,
        )
    }

    private fun state(config: MessengerConfig = this.config, unread: Int = 3) = MessengerSnapshot(
        config = config,
        configLoad = MessengerSnapshot.Load.LOADED,
        conversations = listOf(leyla),
        conversationsLoad = MessengerSnapshot.Load.LOADED,
        unreadTotal = unread,
        news = news,
        faq = faq,
        userName = "Aysel Məmmədova",
    )

    private fun presenter(state: MessengerSnapshot) =
        HomePresenter(ClomniStrings("az", state.config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now)

    private fun snap(name: String, dark: Boolean = false, content: @androidx.compose.runtime.Composable (ClomniTheme) -> Unit) {
        if (dark) paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(nightMode = NightMode.NIGHT))
        val theme = ClomniTheme.make(config.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) { content(theme) }
        }
        semantics.assertTouchTargets(name)
    }

    /** Home with the tab bar: four tabs, Home open, three unread on the conversations; the news and the FAQ card. */
    @Test
    fun homeWithTabBar() {
        val state = state()
        val home = presenter(state).home(state)
        snap("tab_bar_home") { theme -> WithTabBar(home.tabBar, MessengerTab.HOME, theme, {}) { HomeView(home, theme, MessengerActions()) } }
    }

    @Test
    fun homeWithTabBarDark() {
        val state = state()
        val home = presenter(state).home(state)
        snap("tab_bar_home_dark", dark = true) { theme ->
            WithTabBar(home.tabBar, MessengerTab.HOME, theme, {}) { HomeView(home, theme, MessengerActions()) }
        }
    }

    /**
     * Home's news card with news_on_home at its default: two of three news, "Hamısı" under them; the FAQ card: the
     * first three of four questions, "Hamısı"; without a tab bar. On a tall screen, so the whole page shows.
     */
    @Test
    fun homeNewsAndFaq() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(screenHeight = 3900))
        val third = news.last().copy(id = "news_3", title = "Yeni tarif")
        val state = state(config.copy(home = config.home.copy(tabBar = false))).copy(conversations = emptyList(), news = news + third)
        val home = presenter(state).home(state)
        snap("home_news_faq") { theme -> HomeView(home, theme, MessengerActions()) }
    }

    /** The conversations as a tab: no back arrow, the tab bar with the conversations open. */
    @Test
    fun messagesTab() {
        val state = state()
        val presenter = presenter(state)
        val home = presenter.home(state)
        snap("tab_bar_messages") { theme ->
            WithTabBar(home.tabBar, MessengerTab.MESSAGES, theme, {}) {
                MessagesView(presenter.messages(state), theme, home.header.closeLabel, MessengerActions(), tab = true)
            }
        }
    }

    /** Without the panel's FAQ and news: only Home and the conversations; 99+. */
    @Test
    fun twoTabs() {
        val state = state(config.copy(faqEnabled = false), unread = 120).copy(news = emptyList())
        val home = presenter(state).home(state)
        snap("tab_bar_two_tabs") { theme -> WithTabBar(home.tabBar, MessengerTab.HOME, theme, {}) { HomeView(home, theme, MessengerActions()) } }
    }

    /** The questions as a tab: the search field, then the questions in one card. */
    @Test
    fun faqList() {
        val state = state()
        val presenter = presenter(state)
        snap("faq_list") { theme ->
            WithTabBar(presenter.home(state).tabBar, MessengerTab.FAQ, theme, {}) {
                FaqListView(presenter.faq(state), "", {}, theme, MessengerActions(), tab = true)
            }
        }
    }

    /** Without a tab bar (from the FAQ card's "Hamısı"): back, a search with nothing found. */
    @Test
    fun faqSearchedNothing() {
        val state = state(config.copy(home = config.home.copy(tabBar = false)))
        val presenter = presenter(state)
        snap("faq_search_empty") { theme -> FaqListView(presenter.faq(state, "kredit"), "kredit", {}, theme, MessengerActions()) }
    }

    /** An answer, drawn as a news item. */
    @Test
    fun faqAnswer() {
        val state = state()
        val answer = presenter(state).faqItem(state, "faq_1")!!
        snap("faq_answer") { theme -> NewsView(answer, theme, {}, {}, {}) }
    }

    /** All the news, from "Hamısı" without a tab bar. */
    @Test
    fun newsList() {
        val state = state(config.copy(home = config.home.copy(tabBar = false)))
        snap("news_list") { theme -> NewsListView(presenter(state).newsList(state), theme, MessengerActions()) }
    }

    // The conversation

    private fun chat(snapshot: ChatSnapshot) =
        ChatPresenter(ClomniStrings("az", snapshot.config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now).screen(snapshot)

    private fun conversation(vararg messages: ai.clomni.messenger.protocol.Message) = ChatSnapshot(
        config = Fixture.exampleConfig,
        conversation = ChatFixture.conversation("open", """{"name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png","online":true}"""),
        messages = messages.toList(),
        load = MessengerSnapshot.Load.LOADED,
    )

    /** Deleted by the user and by the operator: neutral bubbles, "Bu mesaj silindi" in italics, the time kept. */
    @Test
    fun deletedMessages() {
        val operator = ChatFixture.message("02-text-operator-markdown.json", "seq" to 3, "created_at" to "2026-10-01T10:30:30Z")
        val screen = chat(
            conversation(
                ChatFixture.message("03-text-user.json", "content" to mapOf("type" to "deleted"), "reply_to" to JsonNull),
                ChatFixture.message("66-reply-user-to-operator.json", "seq" to 2, "created_at" to "2026-10-01T10:30:10Z"),
                operator.copy(content = MessageContent.Deleted),
                ChatFixture.message("02-text-operator-markdown.json", "id" to "msg_f02b", "seq" to 4, "created_at" to "2026-10-01T10:31:00Z"),
            ),
        )
        for (dark in listOf(false, true)) {
            snap("chat_deleted_${if (dark) "dark" else "light"}", dark) { theme -> WithVoice { ChatScreenView(screen, theme, ChatActions()) } }
        }
    }

    /** A long press on the user's own message: "Cavabla", "Kopyala" and «Sil» in red, under the bubble. */
    @Test
    fun deleteMenu() {
        val screen = chat(conversation(ChatFixture.message("03-text-user.json")))
        val bubble = screen.items.filterIsInstance<ChatItem.BubbleItem>().single().bubble
        snap("chat_delete_menu") { theme ->
            CompositionLocalProvider(
                LocalTranscript provides TranscriptLinks(screen.replyLabel, screen.copyLabel, screen.deleteLabel, screen.deleteConfirm),
            ) {
                Column(Modifier.fillMaxSize().background(theme.colors.background.color).padding(16.dp)) {
                    BubbleRow(bubble, theme, ChatActions())
                    Box(Modifier.fillMaxWidth(), Alignment.CenterEnd) { MessageMenuContent(bubble, theme, {}, {}, {}) }
                }
            }
        }
    }

    /** "Mesaj silinsin?" over the dimmed conversation. */
    @Test
    fun deleteConfirm() {
        val screen = chat(conversation(ChatFixture.message("03-text-user.json")))
        snap("chat_delete_confirm") { theme ->
            Box(Modifier.fillMaxSize()) {
                WithVoice { ChatScreenView(screen, theme, ChatActions()) }
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.32f)).padding(24.dp), Alignment.Center) {
                    DeleteDialogContent(screen.deleteConfirm, theme, {}, {})
                }
            }
        }
    }

    /** The deleted bubble has no menu: nothing to reply to, copy or delete. */
    @Test
    fun aDeletedBubbleHasNoMenu() {
        val screen = chat(conversation(ChatFixture.message("03-text-user.json", "content" to mapOf("type" to "deleted"))))
        val bubble = screen.items.filterIsInstance<ChatItem.BubbleItem>().single().bubble
        org.junit.Assert.assertTrue(bubble.body is Bubble.DeletedBody)
        org.junit.Assert.assertFalse(bubble.hasMenu)
    }
}
