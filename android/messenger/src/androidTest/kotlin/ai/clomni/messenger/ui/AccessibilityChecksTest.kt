package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomePresenter
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.TimeZone

/**
 * Brief 8·7.6 on a device: Google's Accessibility Test Framework (what Accessibility Scanner runs: touch target size,
 * contrast, labels, duplicate descriptions) over Home and a conversation, light and dark; and a new incoming message
 * is announced.
 */
@RunWith(AndroidJUnit4::class)
class AccessibilityChecksTest {
    @get:Rule
    val compose = createComposeRule()

    private val protocol = ProtocolJson()
    private val utc = TimeZone.getTimeZone("UTC")
    private val now = 1_790_850_720_000L

    private val config: MessengerConfig = protocol.parseConfig(
        """{"version":1,"brand":{"name":"Example","primary_color":"#1F9D63"},
            "team":{"show":true,"avatars":[],"reply_time":"Adətən bir neçə dəqiqəyə cavab veririk"},
            "home":{"cards":["send","recent","channels"],
                    "channels":[{"type":"instagram","url":"https://instagram.com/example"},{"type":"email","url":"mailto:support@example.com"}]},
            "languages":["az","en","ru"],"powered_by":true}""",
    )!!

    private fun message(id: String, sender: String, content: String, at: String = "2026-10-01T10:30:00Z"): ai.clomni.messenger.protocol.Message {
        val buttons = content.contains("buttons")
        return protocol.parseMessage(
            """{"id":"$id","conversation_id":"conv_1","seq":${id.filter(Char::isDigit)},"client_id":null,"sender":$sender,
                "type":"${if (buttons) "quick_replies" else "text"}","content":$content,"created_at":"$at","lang":"az",
                "flow":${if (buttons) """{"flow_id":"f","node_id":"n","version":1,"interactive":true}""" else "null"},
                "fallback_text":"…","meta":{}}""",
        )!!
    }

    private val bot = """{"type":"bot","id":"bot_default","name":"Clomni"}"""
    private val user = """{"type":"user","id":"u_1"}"""
    private val greeting = message("m1", bot, """{"text":"Salam! Zəhmət olmasa dil seçin."}""")
    private val languages = message(
        "m2",
        bot,
        """{"text":"Please choose your language.","layout":"vertical","input_disabled":false,
            "buttons":[{"id":"az","title":"Azərbaycan dili","payload":"set_lang:az"},
                       {"id":"en","title":"English","payload":"set_lang:en"},
                       {"id":"ru","title":"Русский","payload":"set_lang:ru"}]}""",
    )

    private fun chat(vararg messages: ai.clomni.messenger.protocol.Message) = ChatPresenter(ClomniStrings("az"), utc, now).screen(
        ChatSnapshot(config = config, messages = messages.toList(), answerable = setOf("m2"), load = MessengerSnapshot.Load.LOADED),
    )

    @Test
    fun homePasses() {
        val state = MessengerSnapshot(
            config = config,
            configLoad = MessengerSnapshot.Load.LOADED,
            conversationsLoad = MessengerSnapshot.Load.LOADED,
            userName = "Aysel",
        )
        val presenter = HomePresenter(ClomniStrings("az"), utc, now)
        var dark by mutableStateOf(false)
        compose.setContent {
            HomeView(presenter.home(state), ClomniTheme.make(config.brand, dark), MessengerActions())
        }
        compose.enableAccessibilityChecks()
        compose.onRoot().tryPerformAccessibilityChecks()
        dark = true
        compose.waitForIdle()
        compose.onRoot().tryPerformAccessibilityChecks()
    }

    @Test
    fun conversationPasses() {
        compose.setContent { ChatScreenView(chat(greeting, languages), ClomniTheme.make(config.brand, false), ChatActions()) }
        compose.enableAccessibilityChecks()
        compose.onRoot().tryPerformAccessibilityChecks()
    }

    /** The bot's answer arrives while the conversation is open: TalkBack reads it out; the user's own message is not news. */
    @Test
    fun aNewIncomingMessageIsAnnounced() {
        var screen by mutableStateOf(chat(greeting))
        compose.setContent { ChatScreenView(screen, ClomniTheme.make(config.brand, false), ChatActions()) }
        val announced = SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite)
        compose.onAllNodes(announced).assertCountEquals(0)
        screen = chat(greeting, message("m3", user, """{"text":"Kömək edin"}""", "2026-10-01T10:31:00Z"))
        compose.waitForIdle()
        compose.onAllNodes(announced).assertCountEquals(0)
        screen = chat(greeting, message("m3", user, """{"text":"Kömək edin"}""", "2026-10-01T10:31:00Z"), languages.copy(seq = 4))
        compose.waitForIdle()
        compose.onAllNodes(announced).assertCountEquals(1)
    }

    /**
     * Test report: TalkBack moving through the screen found the last bot message twice, its bubble and the
     * announcement. Once read out, the announcement keeps no words: the message is in the tree once.
     */
    @Test
    fun anAnnouncedMessageIsInTheTreeOnce() {
        var screen by mutableStateOf(chat(greeting))
        compose.mainClock.autoAdvance = false
        compose.setContent { ChatScreenView(screen, ClomniTheme.make(config.brand, false), ChatActions()) }
        compose.mainClock.advanceTimeByFrame()
        val saying = SemanticsMatcher("says the bot's question") { node ->
            node.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().any { it.contains("Please choose your language") } ||
                node.config.getOrNull(SemanticsProperties.Text).orEmpty().any { it.text.contains("Please choose your language") }
        }
        screen = chat(greeting, languages.copy(seq = 4))
        compose.mainClock.advanceTimeBy(500)
        compose.onAllNodes(saying, useUnmergedTree = false).assertCountEquals(2)
        compose.mainClock.advanceTimeBy(ANNOUNCED_MS)
        compose.onAllNodes(saying, useUnmergedTree = false).assertCountEquals(1)
    }
}
