package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.VoicePlayer.Phase
import ai.clomni.messenger.presentation.VoicePlayer.Track
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** What the voice bubble says and reads out (as iOS's VoiceNoteTests). */
class VoiceNoteTest {
    private val az = ClomniStrings("az")
    private val audio = ProtocolJson().parseMessage(ProtocolFiles.read("fixtures/100-audio-voice-user.json"))!!.content as MessageContent.Audio
    private val note = VoiceNote.of("msg_f100", audio, outgoing = true)

    @Test
    fun times() {
        assertEquals("0:00", VoiceTime.clock(999))
        assertEquals("0:07", VoiceTime.clock(7_900))
        assertEquals("1:05", VoiceTime.clock(65_000))
        assertEquals("12:00", VoiceTime.clock(720_000))
        assertEquals("0:00", VoiceTime.clock(-5))
        assertEquals("0:14", VoiceTime.length(14_260))
        assertEquals("0:15", VoiceTime.length(14_500))
        assertEquals("a length is never nothing", "0:01", VoiceTime.length(200))
        assertEquals("0:05", VoiceTime.remaining(4_001))
        assertEquals("0:01", VoiceTime.remaining(1))
        assertEquals("0:00", VoiceTime.remaining(0))
        assertEquals("0:00", VoiceTime.remaining(-30))
    }

    @Test
    fun theBubbleShowsTheLengthThenWhatIsLeft() {
        assertEquals(VoicePlayer.Source.Remote("https://app.clomni.ai/f/voice-7d1c.m4a"), note.source)
        assertEquals("0:14", note.time(Track()))
        assertEquals("0:14", note.time(Track(Phase.LOADING)))
        assertEquals("0:11", note.time(Track(Phase.PLAYING, 3_300, 14_260)))
        assertEquals("paused half-heard", "0:11", note.time(Track(Phase.PAUSED, 3_300, 14_260)))
        assertEquals("paused at the start: its length", "0:14", note.time(Track(Phase.PAUSED, 0, 14_260)))
        assertEquals("the file's own length wins", "0:20", note.time(Track(Phase.IDLE, 0, 20_000)))
        val unknown = note.copy(durationMs = null)
        assertEquals("0:00", unknown.time(Track()))
        assertEquals("0:03", unknown.time(Track(Phase.PLAYING, 3_300, null)))
    }

    @Test
    fun talkBackReadsWhatItIsAndHowLong() {
        assertEquals("Səsli mesaj, 0:14", note.accessibilityLabel(Track(), az))
        assertEquals("Səsli mesaj", note.copy(durationMs = null).accessibilityLabel(Track(), az))
        assertEquals("Səsli mesaj, 1:01", note.copy(durationMs = null).accessibilityLabel(Track(durationMs = 61_000), az))
        assertEquals("Voice message, 0:14", note.accessibilityLabel(Track(), ClomniStrings("en")))
        assertEquals("Голосовое сообщение, 0:14", note.accessibilityLabel(Track(), ClomniStrings("ru")))
    }

    @Test
    fun theUsersOwnOnItsWayPlaysFromTheDisk() {
        val file = File("voice-1.m4a")
        val sending = VoiceNote.sending("client-1", file, 3_000, listOf(1, 2), uploading = true)
        assertEquals(VoicePlayer.Source.Local(file), sending.source)
        assertEquals(true to true, sending.outgoing to sending.sending)
        assertEquals("0:03", sending.time(Track()))
        assertEquals(false, VoiceNote.of("msg_1", audio, outgoing = false).sending)
    }

    @Test
    fun theRecordersTexts() {
        assertEquals("Ləğv etmək üçün sürüşdürün", az[ClomniStrings.Key.VOICE_SLIDE_TO_CANCEL])
        assertEquals("Yazmaq üçün basıb saxlayın", az[ClomniStrings.Key.VOICE_HOLD_TO_RECORD])
        assertEquals("Ən çox 5 dəqiqə", az.format(ClomniStrings.Key.VOICE_MAX_LENGTH, 5))
        assertEquals("Up to 1 min", ClomniStrings("en").format(ClomniStrings.Key.VOICE_MAX_LENGTH, 1))
        // The panel can rename them like any other text.
        assertEquals("Səs yaz", ClomniStrings("az", mapOf("voice_record" to "Səs yaz"))[ClomniStrings.Key.VOICE_RECORD])
    }
}
