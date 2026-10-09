package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.VoiceRecording.Effect
import ai.clomni.messenger.presentation.VoiceRecording.Permission
import ai.clomni.messenger.presentation.VoiceRecording.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The microphone button's rules, without a microphone (the same cases as iOS's VoiceRecordingTests). */
class VoiceRecordingTest {
    private val voice = VoiceRecording(maxMs = 300_000)

    private fun recordFor(ms: Long, step: Long = 50, level: Float = 0.5f) {
        var at = 0L
        while (at < ms) {
            at += step
            voice.tick(at, level)
        }
    }

    @Test
    fun holdThenLetGoSends() {
        assertEquals(listOf(Effect.Start), voice.press(Permission.GRANTED))
        assertEquals(State.Holding(0, 0f, 0f), voice.state)
        recordFor(2_000)
        assertEquals(State.Holding(2_000, 0f, 0f), voice.state)
        val sent = voice.release().single() as Effect.Send
        assertEquals(Waveform.POINTS, sent.waveform.size)
        assertEquals(50, sent.waveform.first())
        assertEquals(State.Idle, voice.state)
    }

    @Test
    fun aShortPressIsNoMessage() {
        voice.press(Permission.GRANTED)
        recordFor(650)
        assertEquals(listOf(Effect.Discard(animated = false), Effect.HoldHint), voice.release())
        assertEquals(State.Idle, voice.state)
        // From MIN_MS it is one.
        voice.press(Permission.GRANTED)
        recordFor(VoiceRecording.MIN_MS)
        assertTrue(voice.release().single() is Effect.Send)
    }

    @Test
    fun slidingLeftThrowsItAway() {
        voice.press(Permission.GRANTED)
        recordFor(1_000)
        assertEquals(emptyList<Effect>(), voice.drag(-60f, 4f))
        assertEquals(State.Holding(1_000, 0.5f, 0f), voice.state)
        assertEquals(listOf(Effect.Discard(animated = true)), voice.drag(-VoiceRecording.CANCEL_DP, 0f))
        assertEquals(State.Idle, voice.state)
        assertEquals("the finger coming up afterwards sends nothing", emptyList<Effect>(), voice.release())
    }

    @Test
    fun slidingUpLocksThenStopListenSend() {
        voice.press(Permission.GRANTED)
        recordFor(1_000)
        voice.drag(0f, -45f)
        assertEquals(State.Holding(1_000, 0f, 0.5f), voice.state)
        assertEquals(listOf(Effect.Locked), voice.drag(-10f, -VoiceRecording.LOCK_DP))
        assertEquals(State.Locked(1_000), voice.state)
        assertEquals("the hand can go", emptyList<Effect>(), voice.release())
        recordFor(3_000)
        assertEquals(State.Locked(3_000), voice.state)
        assertEquals(listOf(Effect.Stop), voice.stop())
        assertEquals(State.Review(3_000), voice.state)
        assertEquals("ticks after the stop change nothing", emptyList<Effect>(), voice.tick(3_050, 1f))
        assertTrue(voice.send().single() is Effect.Send)
        assertEquals(State.Idle, voice.state)
    }

    @Test
    fun deleteWhileLockedOrListening() {
        voice.press(Permission.GRANTED)
        voice.drag(0f, -200f)
        assertEquals(listOf(Effect.Discard(animated = true)), voice.delete())
        voice.press(Permission.GRANTED)
        voice.drag(0f, -200f)
        recordFor(1_000)
        voice.stop()
        assertEquals(listOf(Effect.Discard(animated = true)), voice.delete())
        assertEquals(State.Idle, voice.state)
    }

    @Test
    fun sendWhileLockedSendsWithoutStopping() {
        voice.press(Permission.GRANTED)
        voice.drag(0f, -200f)
        recordFor(1_500, level = 1f)
        val sent = voice.send().single() as Effect.Send
        assertTrue(sent.waveform.all { it == 100 })
    }

    @Test
    fun theLimitStopsItForReview() {
        val short = VoiceRecording(maxMs = 1_000)
        short.press(Permission.GRANTED)
        assertEquals(emptyList<Effect>(), short.tick(950, 0.2f))
        assertEquals(listOf(Effect.Stop), short.tick(1_000, 0.2f))
        assertEquals(State.Review(1_000), short.state)
        assertEquals("the finger coming up does not send it", emptyList<Effect>(), short.release())
        assertTrue(short.send().single() is Effect.Send)
    }

    @Test
    fun permission() {
        assertEquals(listOf(Effect.AskPermission), voice.press(Permission.UNDECIDED))
        assertEquals(State.Idle, voice.state)
        assertEquals(listOf(Effect.PermissionDenied), voice.press(Permission.DENIED))
        assertEquals(State.Idle, voice.state)
        assertEquals(listOf(Effect.PermissionDenied), voice.pressLocked(Permission.DENIED))
        assertEquals(State.Idle, voice.state)
    }

    @Test
    fun talkBackRecordsLocked() {
        assertEquals(listOf(Effect.Start), voice.pressLocked(Permission.GRANTED))
        assertEquals(State.Locked(0), voice.state)
        recordFor(2_000)
        assertEquals(listOf(Effect.Stop), voice.stop())
    }

    @Test
    fun whatDoesNotApplyIsIgnored() {
        assertEquals(emptyList<Effect>(), voice.drag(-500f, -500f))
        assertEquals(emptyList<Effect>(), voice.release())
        assertEquals(emptyList<Effect>(), voice.stop())
        assertEquals(emptyList<Effect>(), voice.delete())
        assertEquals(emptyList<Effect>(), voice.send())
        assertEquals(emptyList<Effect>(), voice.tick(100, 1f))
        assertEquals(emptyList<Effect>(), voice.fail())
        voice.press(Permission.GRANTED)
        assertEquals("a second finger", emptyList<Effect>(), voice.press(Permission.GRANTED))
        assertEquals(emptyList<Effect>(), voice.stop())
        assertEquals(listOf(Effect.Discard(animated = false)), voice.fail())
        assertEquals(State.Idle, voice.state)
    }

    @Test
    fun aNewRecordingStartsWithNoLevels() {
        voice.press(Permission.GRANTED)
        recordFor(1_000)
        voice.release()
        voice.press(Permission.GRANTED)
        assertEquals(emptyList<Float>(), voice.levels)
        voice.tick(50, 2f)
        assertEquals("clamped", listOf(1f), voice.levels)
    }
}
