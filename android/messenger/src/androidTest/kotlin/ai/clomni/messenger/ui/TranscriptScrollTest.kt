package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.ProtocolJson
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.TimeZone

/**
 * CM-341: a drag up or down that starts on a bubble scrolls the transcript, as one from the empty space beside it does
 * (iOS 18 kept it still when it started on a bubble; on Android the waveform of a voice message took every move).
 * A long conversation of text and voice messages opens at its end; a finger put on the newest bubble and pulled down
 * must take the list with it.
 */
@RunWith(AndroidJUnit4::class)
class TranscriptScrollTest {
    @get:Rule
    val compose = createComposeRule()

    private val protocol = ProtocolJson()

    private fun message(seq: Int, json: String): Message = protocol.parseMessage(
        """{"id":"msg_$seq","conversation_id":"conv_1","sender":{"type":"${if (seq % 2 == 0) "user" else "operator"}","name":"Leyla"},
           "created_at":"2026-10-01T10:${(seq % 60).toString().padStart(2, '0')}:00Z","seq":$seq,"lang":"az","flow":null,
           "fallback_text":"-",$json}""",
    )!!

    private fun text(seq: Int) = message(seq, """"type":"text","content":{"text":"Mesaj nömrə $seq, bir az uzun ki, balon geniş olsun"}""")

    private fun voice(seq: Int) = message(
        seq,
        """"type":"audio","content":{"url":"https://example.com/v$seq.m4a","mime":"audio/mp4","size":4000,"duration_ms":7000,
           "waveform":[10,40,80,60,30,20,50,90,70,40,20,10]}""",
    )

    private fun show(messages: List<Message>) {
        val snapshot = ChatSnapshot(messages = messages, load = MessengerSnapshot.Load.LOADED)
        val screen = ChatPresenter(ClomniStrings("az"), TimeZone.getTimeZone("UTC"), 1_790_850_720_000L).screen(snapshot)
        compose.setContent { ChatScreenView(screen, ClomniTheme.make(null, false), ChatActions()) }
        compose.waitForIdle()
    }

    private fun SemanticsNodeInteraction.top(): Float = fetchSemanticsNode().boundsInRoot.top

    /** Pulls the finger 300 px down from the middle of [node], slowly enough to be a drag, not a fling. */
    private fun dragDown(node: SemanticsNodeInteraction) {
        node.performTouchInput { swipe(center, center + Offset(0f, 300f), durationMillis = 400) }
        compose.waitForIdle()
    }

    @Test
    fun aDragFromATextBubbleScrollsTheList() {
        show((1..40).map(::text))
        val newest = compose.onAllNodesWithContentDescription("Mesaj nömrə 40", substring = true).onFirst()
        val before = newest.top()
        dragDown(newest)
        assertTrue("the newest bubble went down with the list: $before → ${newest.top()}", newest.top() > before + 100f)
    }

    @Test
    fun aDragFromAVoiceBubbleScrollsTheList() {
        show((1..40).map { if (it % 3 == 0) voice(it) else text(it) })
        // The waveform of the newest voice message (39): the part of the bubble that seeks.
        val waveforms = compose.onAllNodesWithContentDescription("Səsli mesaj", substring = true)
        val newest = waveforms.onLast()
        val before = newest.top()
        dragDown(newest)
        assertTrue("the voice bubble went down with the list: $before → ${newest.top()}", newest.top() > before + 100f)
    }
}
