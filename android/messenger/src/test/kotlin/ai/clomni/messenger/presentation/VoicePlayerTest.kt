package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.VoicePlayer.Phase
import ai.clomni.messenger.presentation.VoicePlayer.Source
import ai.clomni.messenger.presentation.VoicePlayer.Speed
import ai.clomni.messenger.presentation.VoicePlayer.Track
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Playing voice messages one at a time, against a fake speaker and fake fetches (as iOS's VoicePlayerTests). */
class VoicePlayerTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val time = FakeTime()
    private val output = FakeOutput()
    private val files = FakeFiles()
    private val player = VoicePlayer(files, output, time)
    private val first = Source.Remote("https://app.clomni.ai/f/1.m4a")
    private val second = Source.Remote("https://app.clomni.ai/f/2.mp3")

    private fun file(name: String) = folder.root.resolve(name).apply { writeText("audio") }

    /** Message "a" fetched, opened and ready: playing. */
    private fun playing(id: String = "a", source: Source = first, length: Long = 10_000) {
        player.toggle(id, source, null)
        files.answer(files.asked.lastIndex, file("$id.m4a"))
        output.listener!!.ready(length)
    }

    @Test
    fun fetchesOpensAndPlaysThenTicks() {
        player.toggle("a", first, 14_260)
        assertEquals(Track(Phase.LOADING, 0, 14_260), player.track("a"))
        assertEquals(listOf(first.url), files.asked.map { it.first })
        files.answer(0, file("a.m4a"))
        assertEquals(listOf("open a.m4a"), output.calls)
        output.listener!!.ready(14_300)
        assertEquals("open a.m4a, play 1.0", output.calls.joinToString())
        assertEquals(Track(Phase.PLAYING, 0, 14_300), player.track("a"))
        output.position = 1_000
        time.advance(VoicePlayer.TICK_MS)
        assertEquals(1_000L, player.track("a").positionMs)
        assertEquals(1_000f / 14_300, player.track("a").progress, 0.0001f)
    }

    @Test
    fun aSecondTapPausesAndAThirdGoesOn() {
        playing()
        output.position = 3_000
        player.toggle("a", first, null)
        assertEquals(Track(Phase.PAUSED, 3_000, 10_000), player.track("a"))
        assertEquals("pause", output.calls.last())
        val pending = time.pending
        time.advance(1_000)
        assertEquals("no ticks while paused", pending, time.pending)
        player.toggle("a", first, null)
        assertEquals(Phase.PLAYING, player.track("a").phase)
        assertEquals("play 1.0", output.calls.last())
        assertEquals("fetched once", 1, files.asked.size)
    }

    @Test
    fun startingAnotherPausesTheFirstWhereItWas() {
        playing("a")
        output.position = 4_000
        player.toggle("b", second, 7_000)
        assertEquals(Track(Phase.PAUSED, 4_000, 10_000), player.track("a"))
        assertEquals(Phase.LOADING, player.track("b").phase)
        files.answer(1, file("b.mp3"))
        output.position = 0
        output.listener!!.ready(7_000)
        assertEquals(Phase.PLAYING, player.track("b").phase)
        // Back to the first: opened again, from where it paused.
        player.toggle("a", first, null)
        assertEquals(Phase.PAUSED, player.track("b").phase)
        files.answer(2, file("a.m4a"))
        output.listener!!.ready(10_000)
        assertEquals(listOf("seek 4000", "play 1.0"), output.calls.takeLast(2))
        assertEquals(Track(Phase.PLAYING, 4_000, 10_000), player.track("a"))
    }

    @Test
    fun speedIsOneForAllAndChangesWhatPlays() {
        assertEquals(Speed.NORMAL, player.speed)
        player.cycleSpeed()
        assertEquals(Speed.FAST, player.speed)
        assertEquals("nothing plays: nothing to tell", 0, output.calls.size)
        playing()
        assertEquals("play 1.5", output.calls.last())
        player.cycleSpeed()
        assertEquals(listOf("rate 2.0"), output.calls.takeLast(1))
        assertEquals("2×", player.speed.label)
        player.cycleSpeed()
        assertEquals(Speed.NORMAL, player.speed)
        assertEquals("rate 1.0", output.calls.last())
    }

    @Test
    fun seekingWhilePlayingAndBeforePlaying() {
        playing()
        player.seek("a", 0.25f, null)
        assertEquals("seek 2500", output.calls.last())
        assertEquals(2_500L, player.track("a").positionMs)
        // Another message, never played: its next play starts there.
        player.seek("b", 0.5f, 8_000)
        assertEquals(Track(Phase.PAUSED, 4_000, 8_000), player.track("b"))
        assertEquals("only the open file moves", "seek 2500", output.calls.last())
        // A length nobody knows yet: nothing to move to.
        player.seek("c", 0.5f, null)
        assertEquals(Track(), player.track("c"))
        // Out of range is the start or the end.
        player.seek("b", 3f, 8_000)
        assertEquals(8_000L, player.track("b").positionMs)
    }

    @Test
    fun theEndGoesBackToTheStart() {
        playing()
        output.position = 10_000
        output.listener!!.finished()
        assertEquals(Track(Phase.IDLE, 0, 10_000), player.track("a"))
        assertEquals(0, time.pending)
        player.toggle("a", first, null)
        assertEquals("opened again", Phase.LOADING, player.track("a").phase)
    }

    @Test
    fun failuresAndTapsWhileLoading() {
        player.toggle("a", first, null)
        files.answer(0, null)
        assertEquals(Phase.FAILED, player.track("a").phase)
        // A tap tries again.
        player.toggle("a", first, null)
        files.answer(1, file("a.m4a"))
        output.listener!!.failed()
        assertEquals(Phase.FAILED, player.track("a").phase)
        // A tap while it loads stops it; the late answer is dropped.
        player.toggle("b", second, null)
        player.toggle("b", second, null)
        assertEquals(Phase.IDLE, player.track("b").phase)
        files.answer(2, file("b.mp3"))
        assertEquals("b never opened", listOf("open a.m4a"), output.calls.filter { it.startsWith("open") })
    }

    @Test
    fun answersForAnEarlierFileAreDropped() {
        player.toggle("a", first, null)
        player.toggle("b", second, null)
        assertEquals(Phase.IDLE, player.track("a").phase)
        files.answer(0, file("a.m4a"))
        assertEquals("a's fetch came too late", 0, output.calls.size)
        files.answer(1, file("b.mp3"))
        val stale = output.listener!!
        player.toggle("a", first, null)
        stale.ready(5_000)
        assertEquals(Phase.LOADING, player.track("a").phase)
        assertEquals(Phase.IDLE, player.track("b").phase)
    }

    @Test
    fun theUsersOwnRecordingPlaysFromTheDisk() {
        val recording = file("voice-1.m4a")
        player.toggle("client-1", Source.Local(recording), 3_000)
        assertEquals(0, files.asked.size)
        assertEquals(listOf("open voice-1.m4a"), output.calls)
        output.listener!!.ready(3_000)
        assertEquals(Phase.PLAYING, player.track("client-1").phase)
    }

    @Test
    fun anInterruptionPausesAndReleaseLetsGo() {
        playing()
        output.position = 2_000
        output.listener!!.interrupted()
        assertEquals(Track(Phase.PAUSED, 2_000, 10_000), player.track("a"))
        player.toggle("a", first, null)
        player.release()
        assertEquals(Phase.PAUSED, player.track("a").phase)
        assertEquals("close", output.calls.last())
        assertEquals(0, time.pending)
    }

    @Test
    fun prefetchLearnsTheLengthOnce() {
        val mp3 = file("b.mp3")
        output.lengths[mp3] = 61_000
        player.prefetch("b", second.url)
        player.prefetch("b", second.url)
        assertEquals(1, files.asked.size)
        files.answer(0, mp3)
        assertEquals(Track(Phase.IDLE, 0, 61_000), player.track("b"))
        // A length already known is not fetched for.
        player.seek("c", 0f, 5_000)
        player.prefetch("c", first.url)
        assertEquals(1, files.asked.size)
    }

    @Test
    fun everyChangeIsHeard() {
        var changes = 0
        player.onChange = { changes++ }
        playing()
        val before = changes
        time.advance(VoicePlayer.TICK_MS * 3)
        assertEquals(before + 3, changes)
    }
}
