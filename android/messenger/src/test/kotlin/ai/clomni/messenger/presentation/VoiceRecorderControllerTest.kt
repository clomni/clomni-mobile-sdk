package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.VoiceRecorderController.Feedback
import ai.clomni.messenger.presentation.VoiceRecorderController.Hint
import ai.clomni.messenger.presentation.VoiceRecording.Permission
import ai.clomni.messenger.presentation.VoiceRecording.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The recorder against a microphone double: what is recorded, sent, kept or thrown away (as iOS's tests). */
class VoiceRecorderControllerTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val time = FakeTime()
    private val mic = FakeMic(time)
    private var permission = Permission.GRANTED
    private var asked = 0
    private val sent = mutableListOf<VoiceClip>()
    private val feedback = mutableListOf<Feedback>()
    private var changes = 0
    private var files = 0

    private fun recorder(maxMs: Long = 300_000) = VoiceRecorderController(
        mic = mic,
        permission = { permission },
        askPermission = { asked++ },
        newFile = { folder.root.resolve("voice-${files++}.m4a") },
        scheduler = time,
        now = { time.now },
        maxMs = maxMs,
        send = { sent += it },
        feedback = { feedback += it },
    ).also { it.onChange = { changes++ } }

    @Test
    fun holdAndLetGoSendsTheRecordingWithItsLengthAndWaveform() {
        val recorder = recorder()
        recorder.press()
        assertEquals(1, mic.started.size)
        assertEquals(listOf(Feedback.START), feedback)
        mic.level = 0.8f
        time.advance(1_500)
        assertEquals(State.Holding(1_500, 0f, 0f), recorder.state)
        assertEquals("a level each 50 ms tick", 30, recorder.levels.size)
        assertTrue("the view hears each tick", changes >= 30)
        recorder.release()
        val clip = sent.single()
        assertEquals(mic.started.single(), clip.file)
        assertEquals(1_500L, clip.durationMs)
        assertEquals(List(Waveform.POINTS) { 80 }, clip.waveform)
        assertTrue(clip.file.exists())
        assertEquals("the clock stops with it", 0, time.pending)
        assertEquals(State.Idle, recorder.state)
    }

    @Test
    fun aShortPressAsksToHoldForTwoSeconds() {
        val recorder = recorder()
        recorder.press()
        time.advance(300)
        recorder.release()
        assertEquals(emptyList<VoiceClip>(), sent)
        assertEquals(1, mic.cancels)
        assertFalse(mic.started.single().exists())
        assertEquals(Hint.HOLD, recorder.hint)
        assertEquals("no bin for a slip", 0, recorder.discards)
        time.advance(1_999)
        assertEquals(Hint.HOLD, recorder.hint)
        time.advance(1)
        assertNull(recorder.hint)
    }

    @Test
    fun slidingAwayThrowsItIntoTheBin() {
        val recorder = recorder()
        recorder.press()
        time.advance(2_000)
        recorder.drag(-130f, 0f)
        assertEquals(1, mic.cancels)
        assertFalse(mic.started.single().exists())
        assertEquals(1, recorder.discards)
        assertEquals(listOf(Feedback.START, Feedback.CANCEL), feedback)
        recorder.release()
        assertEquals(emptyList<VoiceClip>(), sent)
    }

    @Test
    fun lockedStoppedHeardThenSent() {
        val recorder = recorder()
        recorder.press()
        time.advance(1_000)
        recorder.drag(0f, -100f)
        assertEquals(Feedback.LOCK, feedback.last())
        recorder.release()
        time.advance(4_000)
        assertEquals(State.Locked(5_000), recorder.state)
        recorder.stop()
        assertEquals(1, mic.stops)
        val review = recorder.review!!
        assertEquals(5_000L, review.durationMs)
        assertEquals(State.Review(5_000), recorder.state)
        time.advance(10_000)
        assertEquals("nothing records while it is heard", 100, recorder.levels.size)
        recorder.send()
        assertEquals(listOf(review), sent)
        assertNull(recorder.review)
        assertEquals("stopped once", 1, mic.stops)
    }

    @Test
    fun deletedWhileHeard() {
        val recorder = recorder()
        recorder.pressLocked()
        time.advance(2_000)
        recorder.stop()
        val file = recorder.review!!.file
        recorder.delete()
        assertFalse(file.exists())
        assertEquals(1, recorder.discards)
        assertEquals(emptyList<VoiceClip>(), sent)
    }

    @Test
    fun theLimitStopsItAndSaysSo() {
        val recorder = recorder(maxMs = 3_000)
        recorder.press()
        time.advance(3_000)
        assertEquals(State.Review(3_000), recorder.state)
        assertEquals(Hint.LIMIT, recorder.hint)
        assertEquals(1, mic.stops)
        recorder.release()
        assertEquals("letting go does not send it", emptyList<VoiceClip>(), sent)
        recorder.send()
        assertEquals(3_000L, sent.single().durationMs)
    }

    @Test
    fun permission() {
        permission = Permission.UNDECIDED
        val recorder = recorder()
        recorder.press()
        assertEquals(1, asked)
        assertEquals(emptyList<java.io.File>(), mic.started)
        permission = Permission.DENIED
        recorder.press()
        assertEquals(Hint.DENIED, recorder.hint)
        time.advance(VoiceRecorderController.DENIED_HINT_MS)
        assertNull(recorder.hint)
        permission = Permission.GRANTED
        recorder.press()
        assertEquals(1, mic.started.size)
    }

    @Test
    fun aMicrophoneThatWillNotStartOrRecordedNothing() {
        val recorder = recorder()
        mic.starts = false
        recorder.press()
        assertEquals(State.Idle, recorder.state)
        assertEquals("no clock without a recording", 0, time.pending)
        mic.starts = true
        mic.stopsEmpty = true
        recorder.press()
        time.advance(1_000)
        recorder.release()
        assertEquals(emptyList<VoiceClip>(), sent)
        recorder.pressLocked()
        time.advance(1_000)
        recorder.stop()
        assertEquals(State.Idle, recorder.state)
        assertNull(recorder.review)
    }

    @Test
    fun closingThrowsAwayWhatIsBeingRecordedOrHeard() {
        val recorder = recorder()
        recorder.press()
        time.advance(1_000)
        recorder.close()
        assertEquals(State.Idle, recorder.state)
        assertEquals(1, mic.cancels)
        assertEquals(0, time.pending)
        recorder.pressLocked()
        time.advance(1_000)
        recorder.stop()
        val file = recorder.review!!.file
        recorder.close()
        assertFalse(file.exists())
        assertEquals(emptyList<VoiceClip>(), sent)
    }
}
