package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatFixture
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import android.view.View
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import app.cash.paparazzi.RenderExtension
import app.cash.paparazzi.accessibility.AccessibilityRenderExtension
import com.android.resources.NightMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.util.TimeZone

/**
 * Brief 8·7.6 as TalkBack meets it: what each screen reads, in order (from the merged semantics tree), and the screens
 * at font scale 200%, light and dark, and right to left. Every shot also checks the 48 dp targets. The labelled shots
 * (Paparazzi's accessibility overlay) and copies of the rest are in docs/screenshots/accessibility/android.
 */
class AccessibilitySnapshotTest {
    private val semantics = SemanticsCapture()
    private val labels = Toggle(AccessibilityRenderExtension())

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderExtensions = setOf(labels, semantics),
    )

    /** 2026-10-01T10:32Z: two minutes after the fixtures' messages. */
    private val now = 1_790_850_720_000L
    private val utc = TimeZone.getTimeZone("UTC")

    private val leyla: Conversation = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)

    /** Paparazzi's overlay of what TalkBack reads, only for the shots that ask for it. */
    class Toggle(private val extension: RenderExtension) : RenderExtension {
        var on = false

        override fun renderView(contentView: View): View = if (on) extension.renderView(contentView) else contentView
    }

    private fun device(fontScale: Float = 1f, dark: Boolean = false) = paparazzi.unsafeUpdateConfig(
        deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = fontScale, nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT),
    )

    /** Right to left is given to Compose directly: layoutlib mirrors only an app that declares supportsRtl. */
    private fun direction(rtl: Boolean) = if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr

    private fun home(
        name: String,
        tab: Shown = Shown.HOME,
        dark: Boolean = false,
        offline: Boolean = false,
        conversations: List<Conversation> = listOf(leyla),
        rtl: Boolean = false,
    ) {
        val config = Fixture.aparConfig
        val state = MessengerSnapshot(
            config = config,
            configLoad = MessengerSnapshot.Load.LOADED,
            conversations = conversations,
            conversationsLoad = MessengerSnapshot.Load.LOADED,
            userName = "Aysel Məmmədova",
            isOffline = offline,
        )
        val presenter = HomePresenter(ClomniStrings("az", config.strings), utc, now)
        val theme = ClomniTheme.make(config.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true, LocalLayoutDirection provides direction(rtl)) {
                MessengerScreenAt(presenter.home(state), presenter.messages(state), theme, MessengerActions(), tab)
            }
        }
        semantics.assertTouchTargets(name)
    }

    private fun chat(name: String, snapshot: ChatSnapshot, dark: Boolean = false, rtl: Boolean = false) {
        val screen = ChatPresenter(ClomniStrings("az", snapshot.config?.strings.orEmpty()), utc, now).screen(snapshot)
        val theme = ClomniTheme.make(snapshot.config?.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true, LocalLayoutDirection provides direction(rtl)) {
                ChatScreenView(screen, theme, ChatActions())
            }
        }
        semantics.assertTouchTargets(name)
    }

    private fun conversation(vararg messages: Message, answerable: Set<String> = emptySet(), offline: Boolean = false) = ChatSnapshot(
        config = Fixture.aparConfig,
        conversation = ChatFixture.conversation("bot"),
        messages = messages.toList(),
        answerable = answerable,
        load = MessengerSnapshot.Load.LOADED,
        isOffline = offline,
    )

    private val languages = ChatFixture.message("07-language-select.json")
    private fun languageChoice() = conversation(
        ChatFixture.message("01-text-bot.json"),
        ChatFixture.message("03-text-user.json"),
        languages,
        answerable = setOf(languages.id),
    )

    private val form = ChatFixture.message("19-form-contact.json")
    private fun formStep() = conversation(form, answerable = setOf(form.id))

    private fun closed() = conversation(ChatFixture.message("03-text-user.json"), ChatFixture.message("24-system-conversation-closed.json"))
        .copy(conversation = ChatFixture.conversation("closed"))

    private fun assertReads(expected: List<String>) =
        assertEquals(expected.joinToString("\n"), semantics.elements.joinToString("\n"))

    /**
     * DESIGN-PASS-2 6: one close button on every screen, the same size in the same place: a 48 dp target (its 40 dp
     * circle 16 dp from the end edge), at the same height under the top.
     */
    @Test
    fun theCloseButtonIsTheSameEverywhere() {
        fun close(): SemanticsCapture.Element = semantics.elements.single { it.label == "Bağla" }
        home("close_home")
        val onHome = close()
        home("close_messages", Shown.MESSAGES)
        val onList = close()
        chat("close_chat", languageChoice())
        val inChat = close()
        for (element in listOf(onHome, onList, inChat)) {
            assertEquals(48f, element.width, 0.5f)
            assertEquals(48f, element.height, 0.5f)
            assertEquals("its circle 16 dp from the edge", 12f, element.fromEnd, 0.5f)
        }
        assertEquals(onHome.top, onList.top, 0.5f)
        assertEquals(onHome.top, inChat.top, 0.5f)
    }

    /**
     * The bar (list, conversation): its title in the middle of the screen, the same room on both sides however wide the
     * buttons; back and ✕ the same 48 dp circles, 12 dp from their edges, at the same height.
     */
    @Test
    fun theBarsTitleIsInTheMiddle() {
        home("bar_messages", Shown.MESSAGES)
        val title = semantics.elements.single { it.heading }
        assertEquals("Mesajlar", title.label)
        assertEquals("centred on the screen", title.fromStart, title.fromEnd, 0.5f)
        val back = semantics.elements.single { it.label == "Geri" }
        val close = semantics.elements.single { it.label == "Bağla" }
        for (button in listOf(back, close)) {
            assertEquals(48f, button.width, 0.5f)
            assertEquals(48f, button.height, 0.5f)
        }
        assertEquals(12f, back.fromStart, 0.5f)
        assertEquals(12f, close.fromEnd, 0.5f)
        assertEquals(back.top, close.top, 0.5f)
        chat("bar_chat", languageChoice())
        val inChat = semantics.elements.single { it.label == "Geri" }
        assertEquals(back.fromStart, inChat.fromStart, 0.5f)
        assertEquals(back.top, inChat.top, 0.5f)
    }

    // What TalkBack reads, with Paparazzi's overlay

    @Test
    fun homeReads() {
        labels.on = true
        home("home_talkback")
        assertReads(
            listOf(
                "Apar",
                "Bağla [Button]",
                "Salam, Aysel Bizdən nəsə soruşun [heading]",
                "Mesajlar, Oxunmamış mesaj var [Button]",
                "Ən son mesaj. Leyla, 2 dəq: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər. Oxunmamış [Button]",
                "Bizə mesaj göndərin. Adətən bir neçə dəqiqəyə cavab veririk [Button]",
                "Bizi izləyin [heading]",
                "Instagram [Button]",
                "WhatsApp [Button]",
                "LinkedIn [Button]",
                "E-poçt [Button]",
                "Powered by Clomni",
            ),
        )
    }

    @Test
    fun conversationReads() {
        labels.on = true
        chat("chat_talkback", languageChoice())
        assertReads(
            listOf(
                "Geri [Button]",
                "Apar Adətən bir neçə dəqiqəyə cavab veririk [heading]",
                "Bağla [Button]",
                "Bu gün 10:30",
                "Clomni bot, 10:30: Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz.",
                "Siz, 10:35: Gedişim bitmədi, pul çıxılmağa davam edir",
                "Clomni bot, 10:30: Salam, Clomni-yə xoş gəlmisiniz.\nZəhmət olmasa dil seçin.\nPlease choose your language.\nПожалуйста, выберите язык.",
                "Azərbaycan dili, 1-ci, cəmi 3 [Button]",
                "English, 2-ci, cəmi 3 [Button]",
                "Русский, 3-cü, cəmi 3 [Button]",
            ),
        )
    }

    @Test
    fun formReads() {
        labels.on = true
        chat("form_talkback", formStep())
        assertReads(
            listOf(
                "Geri [Button]",
                "Apar Adətən bir neçə dəqiqəyə cavab veririk [heading]",
                "Bağla [Button]",
                "Bu gün 10:30",
                "Clomni bot, 10:30: Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.",
                "Ad, soyad, məcburi [click]",
                "Telefon, məcburi [click]",
                "Email [click]",
                "Göndər [Button]",
                "Mesaj yazın… [click]",
                "Emoji [Button]",
                "Fayl əlavə et [Button]",
            ),
        )
    }

    @Test
    fun messagesReads() {
        home("messages", Shown.MESSAGES)
        assertReads(
            listOf(
                "Geri [Button]",
                "Mesajlar [heading]",
                "Bağla [Button]",
                "Bizə mesaj göndərin. Adətən bir neçə dəqiqəyə cavab veririk [Button]",
                "Leyla, 2 dəq: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər. Oxunmamış [Button]",
            ),
        )
    }

    // Font scale 200%, light and dark

    @Test
    fun homeAt200() = for200 { dark -> home("home_font_200_${mode(dark)}", dark = dark) }

    @Test
    fun messagesAt200() = for200 { dark -> home("messages_font_200_${mode(dark)}", Shown.MESSAGES, dark) }

    @Test
    fun offlineAt200() = for200 { dark -> home("offline_font_200_${mode(dark)}", dark = dark, offline = true) }

    @Test
    fun conversationAt200() = for200 { dark -> chat("chat_font_200_${mode(dark)}", languageChoice(), dark) }

    @Test
    fun formAt200() = for200 { dark -> chat("form_font_200_${mode(dark)}", formStep(), dark) }

    @Test
    fun closedAt200() = for200 { dark -> chat("closed_font_200_${mode(dark)}", closed(), dark) }

    private fun mode(dark: Boolean) = if (dark) "dark" else "light"

    private fun for200(shoot: (Boolean) -> Unit) {
        for (dark in listOf(false, true)) {
            device(fontScale = 2f, dark = dark)
            shoot(dark)
        }
    }

    // Right to left (brief 7.6: start/end, for a future RTL language)

    @Test
    fun conversationRightToLeft() = chat("chat_rtl", languageChoice(), rtl = true)

    @Test
    fun homeRightToLeft() = home("home_rtl", rtl = true)
}
