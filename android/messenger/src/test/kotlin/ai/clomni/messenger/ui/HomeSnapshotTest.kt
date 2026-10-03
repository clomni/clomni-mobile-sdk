package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.Density
import com.android.resources.NightMode
import org.junit.Rule
import org.junit.Test
import java.util.TimeZone

/** Home and Messages as Paparazzi draws them (Roboto, the API 36 framework), from protocol fixtures 42 and 43. */
class HomeSnapshotTest {
    private val semantics = SemanticsCapture()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderExtensions = setOf(semantics),
    )

    /** 2026-10-01T10:32Z: two minutes after the fixtures' messages. */
    private val now = 1_790_850_720_000L

    private val leyla: Conversation = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)

    private fun snap(
        name: String,
        state: MessengerSnapshot,
        tab: Shown = Shown.HOME,
        dark: Boolean = false,
    ) {
        val config = state.config
        val presenter = HomePresenter(ClomniStrings("az", config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now)
        val theme = ClomniTheme.make(config?.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                MessengerScreenAt(presenter.home(state), presenter.messages(state), theme, MessengerActions(), tab)
            }
        }
        semantics.assertTouchTargets(name)
    }

    private fun loaded(
        config: MessengerConfig? = Fixture.aparConfig,
        conversations: List<Conversation> = listOf(leyla),
        user: String? = "Aysel Məmmədova",
    ) = MessengerSnapshot(
        config = config,
        configLoad = MessengerSnapshot.Load.LOADED,
        conversations = conversations,
        conversationsLoad = MessengerSnapshot.Load.LOADED,
        userName = user,
    )

    @Test
    fun homeLight() = snap("home_light", loaded())

    @Test
    fun homeDark() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(nightMode = NightMode.NIGHT))
        snap("home_dark", loaded(), dark = true)
    }

    @Test
    fun homeSkeleton() = snap("home_skeleton", MessengerSnapshot(userName = "Aysel Məmmədova"))

    @Test
    fun homeError() = snap(
        "home_error",
        MessengerSnapshot(configLoad = MessengerSnapshot.Load.FAILED, conversationsLoad = MessengerSnapshot.Load.FAILED),
    )

    @Test
    fun homeOffline() = snap("home_offline", loaded().copy(isOffline = true, configLoad = MessengerSnapshot.Load.FAILED))

    /** Fixture 43: only "new conversation", no channels, no team, no reply time; the SDK's own texts. */
    @Test
    fun homeMinimalConfig() = snap("home_minimal_config", loaded(Fixture.minimalConfig, emptyList(), user = null))

    @Test
    fun homeFontScale200() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 2f))
        snap("home_font_scale_200", loaded())
    }

    /** Every channel mark the SDK knows. */
    @Test
    fun homeAllChannels() {
        val channels = listOf("instagram", "whatsapp", "telegram", "facebook", "messenger", "linkedin", "youtube", "tiktok", "x")
            .map { MessengerConfig.Channel(it, "https://$it.com/apar") } +
            listOf(MessengerConfig.Channel("email", "mailto:support@apar.az"), MessengerConfig.Channel("phone", "tel:+994125550000"),
                MessengerConfig.Channel("site", "https://apar.az"))
        val config = Fixture.aparConfig.let { it.copy(home = it.home.copy(channels = channels)) }
        snap("home_all_channels", loaded(config, emptyList()))
    }

    /** The list's first opening: the indicator in the middle (DESIGN-PASS 5). */
    @Test
    fun messagesLoading() = snap(
        "messages_loading",
        loaded(conversations = emptyList()).copy(conversationsLoad = MessengerSnapshot.Load.LOADING),
        Shown.MESSAGES,
    )

    @Test
    fun messagesEmpty() = snap("messages_empty", loaded(conversations = emptyList()), Shown.MESSAGES)

    @Test
    fun messagesList() = snap(
        "messages_list",
        loaded(
            conversations = listOf(
                leyla,
                Fixture.conversation("conv_2", "03-text-user.json", assignee = "Rauf", at = "2026-10-01T09:10:00Z"),
                Fixture.conversation("conv_3", "10-apar-level2-S-chips.json", at = "2026-09-20T12:00:00Z"),
            ),
        ),
        Shown.MESSAGES,
    )

    @Test
    fun messagesDark() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(nightMode = NightMode.NIGHT))
        snap("messages_dark", loaded(), Shown.MESSAGES, dark = true)
    }

    /**
     * The reference's Home (docs/ui-reference.html 4.1) at its own size, 282×602 dp at 1.5×, with its data: Apar,
     * Aysel, Leyla's "Balansınıza 2 AZN qaytarıldı." two minutes ago, unread.
     */
    @Test
    fun homeReference() {
        paparazzi.unsafeUpdateConfig(
            deviceConfig = DeviceConfig.PIXEL_5.copy(screenWidth = 423, screenHeight = 903, xdpi = 240, ydpi = 240, density = Density.HIGH),
        )
        val message = leyla.lastMessage!!.copy(content = MessageContent.Text("Balansınıza 2 AZN qaytarıldı."))
        snap("home_reference", loaded(conversations = listOf(leyla.copy(lastMessage = message))))
    }

    private val news = ProtocolJson().parseNews(ProtocolFiles.read("fixtures/61-news.json"))!!

    /** CM-114: Home with the news card (fixture 61). */
    @Test
    fun homeWithNews() = snap("home_news", loaded().copy(news = news))

    /** CM-114: a news item's own screen: picture, title, date, text, button. */
    @Test
    fun newsItem() {
        val state = loaded().copy(news = news)
        val presenter = HomePresenter(ClomniStrings("az", state.config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now)
        val screen = presenter.news(state, "news_12")!!
        paparazzi.snapshot("news_item") {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                NewsView(screen, ClomniTheme.make(state.config?.brand, false), {}, {}, {})
            }
        }
        semantics.assertTouchTargets("news_item")
    }
}
