package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatFixture
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import com.android.resources.Density
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.util.TimeZone

/** 2026-10-01T10:32Z: two minutes after most fixtures. */
private const val NOW = 1_790_850_720_000L

private fun present(snapshot: ChatSnapshot, now: Long = NOW) =
    ChatPresenter(ClomniStrings("az", snapshot.config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now).screen(snapshot)

/**
 * Every message fixture of protocol/fixtures/index.json in the conversation screen, light and dark, the whole
 * conversation laid out (the picture is as tall as it is).
 */
class ChatFixtureSnapshotTest {
    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderingMode = SessionParams.RenderingMode.SHRINK,
    )

    @Test
    fun everyMessageFixture() {
        val protocol = ProtocolJson()
        val config = Fixture.aparConfig
        var rendered = 0
        for (entry in ProtocolFiles.index("fixtures")) {
            if (entry.schema != "message.json") continue
            // A message the parser drops (no seq, say) has nothing to show.
            val message = protocol.parseMessage(ProtocolFiles.read(entry.path)) ?: continue
            val screen = present(
                ChatSnapshot(
                    config = config,
                    messages = listOf(message),
                    answerable = if (message.flow?.interactive == true) setOf(message.id) else emptySet(),
                    load = MessengerSnapshot.Load.LOADED,
                ),
            )
            val name = entry.path.removePrefix("fixtures/").removeSuffix(".json")
            for (dark in listOf(false, true)) {
                val theme = ClomniTheme.make(config.brand, dark)
                paparazzi.snapshot("$name-${if (dark) "dark" else "light"}") {
                    CompositionLocalProvider(LocalInspectionMode provides true) {
                        ChatScreenView(screen, theme, ChatActions(), lazy = false)
                    }
                }
            }
            rendered++
        }
        assertTrue("$rendered", rendered >= 35)
    }
}

/** The conversation screen's states on a phone, as the app lays them out (brief 8·7.4, 7.5). */
class ChatSnapshotTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, theme = "android:Theme.Material.Light.NoActionBar")

    private val protocol = ProtocolJson()

    private fun snap(
        name: String,
        snapshot: ChatSnapshot,
        dark: Boolean = false,
        now: Long = NOW,
        draft: String = "",
        safeAreas: Boolean = false,
    ) {
        val screen = present(snapshot, now)
        val theme = ClomniTheme.make(snapshot.config?.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                Scene(theme, safeAreas) { ChatScreenView(screen, theme, ChatActions(), draft = draft) }
            }
        }
    }

    /**
     * [safeAreas]: the reference phone's 46 dp status bar and 20 dp home indicator around the screen, so the comparison
     * pictures line up; Paparazzi draws neither.
     */
    @Composable
    private fun Scene(theme: ClomniTheme, safeAreas: Boolean, content: @Composable () -> Unit) {
        if (!safeAreas) return content()
        Column(Modifier.fillMaxSize().background(theme.colors.background.color)) {
            Spacer(Modifier.height(46.dp))
            Column(Modifier.weight(1f)) { content() }
            Spacer(Modifier.height(20.dp))
        }
    }

    private fun loaded(vararg messages: Message, answerable: Set<String> = emptySet()) = ChatSnapshot(
        config = Fixture.aparConfig,
        conversation = ChatFixture.conversation("bot"),
        messages = messages.toList(),
        answerable = answerable,
        load = MessengerSnapshot.Load.LOADED,
    )

    private val leyla = """{"name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png","online":true}"""

    /** A message of the reference's conversations. */
    private fun message(id: String, seq: Int, at: String, sender: String, type: String, content: String): Message =
        protocol.parseMessage(
            """{"id":"$id","conversation_id":"conv_5521","type":"$type","sender":$sender,"created_at":"2026-10-01T$at",
               "seq":$seq,"lang":"az","flow":${if (type == "quick_replies") """{"flow_id":"f","node_id":"n$seq","interactive":true}""" else "null"},
               "content":$content,"fallback_text":"-"}""",
        )!!

    private val bot = """{"type":"bot","id":"bot_default","name":"Clomni","avatar_url":"https://app.clomni.ai/a/bot.png"}"""
    private val user = """{"type":"user","id":"usr_1"}"""
    private val operator = """{"type":"operator","id":"op_42","name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png"}"""

    @Test
    fun skeleton() = snap("chat_skeleton", ChatSnapshot(config = Fixture.aparConfig, conversation = ChatFixture.conversation("bot")))

    @Test
    fun loadFailedOffline() = snap(
        "chat_error_offline",
        ChatSnapshot(config = Fixture.aparConfig, load = MessengerSnapshot.Load.FAILED, isOffline = true),
    )

    @Test
    fun offline() = snap("chat_offline", loaded(ChatFixture.message("01-text-bot.json")).copy(isOffline = true))

    @Test
    fun closedConversation() = snap(
        "chat_closed",
        loaded(ChatFixture.message("03-text-user.json"), ChatFixture.message("24-system-conversation-closed.json"))
            .copy(conversation = ChatFixture.conversation("closed")),
    )

    /** input_disabled: the composer asks for a button, the step's chips with "← Geri". */
    @Test
    fun inputDisabled() {
        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        snap("chat_input_disabled", loaded(step, answerable = setOf(step.id)))
    }

    @Test
    fun operatorHeaderAndTyping() = snap(
        "chat_operator_typing",
        loaded(
            ChatFixture.message("03-text-user.json"),
            ChatFixture.message("23-system-operator-joined.json"),
            ChatFixture.message("31-operator-no-avatar.json", "created_at" to "2026-10-01T10:40:30Z"),
        ).copy(conversation = ChatFixture.conversation("open", leyla), typing = Sender(SenderType.OPERATOR, name = "Leyla")),
        now = 1_790_851_260_000L,
    )

    @Test
    fun failedToSend() {
        val failed = PendingMessage("conv_5521", ClientMessage.Text("Gedişim bitmədi"), "Gedişim bitmədi", NOW, PendingMessage.State.FAILED, 3)
        val sending = PendingMessage("conv_5521", ClientMessage.Text("Kömək edin"), "Kömək edin", NOW)
        snap("chat_failed", loaded(ChatFixture.message("01-text-bot.json")).copy(pending = listOf(failed, sending)))
    }

    @Test
    fun afterHours() {
        val config = Fixture.aparConfig.let {
            it.copy(team = it.team.copy(officeHours = it.team.officeHours?.copy(openNow = false, nextOpenAt = 1_790_917_200_000L)))
        }
        snap("chat_after_hours", loaded(ChatFixture.message("01-text-bot.json")).copy(config = config))
    }

    @Test
    fun formLiveDark() {
        val form = ChatFixture.message("19-form-contact.json")
        snap(
            "chat_form_dark",
            loaded(form, answerable = setOf(form.id)).copy(known = mapOf("name" to "Aysel Məmmədova")),
            dark = true,
        )
    }

    @Test
    fun fontScale200() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 2f))
        val languages = ChatFixture.message("07-language-select.json")
        snap("chat_font_scale_200", loaded(languages, answerable = setOf(languages.id)))
    }

    // The reference (docs/ui-reference.html 4.2, 4.3) at its own size, 282×602 dp at 1.5×, with its data.

    private fun reference() = paparazzi.unsafeUpdateConfig(
        deviceConfig = DeviceConfig.PIXEL_5.copy(screenWidth = 423, screenHeight = 903, xdpi = 240, ydpi = 240, density = Density.HIGH),
    )

    private fun languageChoice(): List<Message> = listOf(
        message("m1", 1, "10:30:00Z", bot, "text", """{"text":"Salam, Clomni-yə xoş gəlmisiniz. Zəhmət olmasa dil seçin."}"""),
        message(
            "m2", 2, "10:30:00Z", bot, "quick_replies",
            """{"text":"Please choose your language.\nПожалуйста, выберите язык.","layout":"vertical","input_disabled":false,
               "buttons":[{"id":"az","title":"Azərbaycan dili","icon":"🇦🇿","payload":"set_lang:az"},
                          {"id":"en","title":"English","icon":"🇬🇧","payload":"set_lang:en"},
                          {"id":"ru","title":"Русский","icon":"🇷🇺","payload":"set_lang:ru"}]}""",
        ),
    )

    /** 4.2, before the choice. */
    @Test
    fun referenceLanguageChoice() {
        reference()
        snap("reference_4_2_before", loaded(*languageChoice().toTypedArray(), answerable = setOf("m2")), now = 1_790_850_620_000L, safeAreas = true)
    }

    /** 4.2, after the choice: the choice as the user's message ("Göndərildi"), then the bot typing. */
    @Test
    fun referenceLanguageChosen() {
        reference()
        val chosen = message("m3", 3, "10:31:00Z", user, "text", """{"text":"🇦🇿 Azərbaycan dili"}""")
        snap(
            "reference_4_2_after",
            loaded(*(languageChoice() + chosen).toTypedArray()).copy(typing = Sender(SenderType.BOT)),
            now = 1_790_850_680_000L,
            safeAreas = true,
        )
    }

    /** 4.3, path S: chips with "← Geri", the composer locked. */
    @Test
    fun referenceFlowStep() {
        reference()
        val messages = listOf(
            message("m1", 1, "10:28:00Z", bot, "text", """{"text":"**Salam!** Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz."}"""),
            message("m2", 2, "10:28:00Z", bot, "text", """{"text":"Aşağıdakı başlıqlardan sizə uyğun olanı seçin."}"""),
            message("m3", 3, "10:29:40Z", user, "text", """{"text":"Aktiv gediş ilə bağlı problem yaşayıram"}"""),
            ChatFixture.message("10-apar-level2-S-chips.json", "seq" to 4, "created_at" to "2026-10-01T10:30:00Z"),
        )
        snap("reference_4_3_flow", loaded(*messages.toTypedArray(), answerable = setOf("msg_f10")), now = 1_790_850_620_000L, safeAreas = true)
    }

    /** 4.3, the operator: queue and join lines, Leyla's run, "Oxundu", a message being written. */
    @Test
    fun referenceOperator() {
        reference()
        val messages = listOf(
            message("m1", 1, "10:30:00Z", user, "text", """{"text":"Gedişim bitmədi, pul çıxılmağa davam edir"}"""),
            message("m2", 2, "10:30:10Z", """{"type":"system"}""", "system", """{"event":"waiting_in_queue","text":"Sizi komandaya yönləndiririk"}"""),
            message("m3", 3, "10:30:40Z", """{"type":"system"}""", "system", """{"event":"operator_joined","text":"Leyla söhbətə qoşuldu"}"""),
            message("m4", 4, "10:31:00Z", operator, "text", """{"text":"Salam, Aysel. Gedişinizi yoxlayıram."}"""),
            message("m5", 5, "10:31:30Z", operator, "text", """{"text":"Gedişi bitirdim, balansınıza 2 AZN qaytarıldı."}"""),
            message("m6", 6, "10:31:50Z", user, "text", """{"text":"Çox sağ olun"}"""),
        )
        snap(
            "reference_4_3_operator",
            loaded(*messages.toTypedArray()).copy(conversation = ChatFixture.conversation("open", leyla), readUpTo = 6),
            now = 1_790_850_720_000L,
            draft = "Velosiped Nizami küçəsindədir",
            safeAreas = true,
        )
    }
}
