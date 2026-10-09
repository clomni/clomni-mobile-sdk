package ai.clomni.messenger.presentation

import org.junit.Assert.assertEquals
import org.junit.Test

/** The waveform's numbers: the same expectations as iOS's WaveformTests. */
class WaveformTest {
    private fun assertBars(expected: List<Float>, actual: List<Float>) {
        assertEquals(expected.size, actual.size)
        expected.zip(actual).forEach { (want, got) -> assertEquals(want, got, 0.0001f) }
    }

    private val half = Waveform.FLOOR + (1 - Waveform.FLOOR) * 0.5f

    @Test
    fun loudnessToLevels() {
        assertEquals(1f, Waveform.level(0.0))
        assertEquals(0.5f, Waveform.level(-25.0))
        assertEquals(0f, Waveform.level(-50.0))
        assertEquals(0f, Waveform.level(-160.0))
        assertEquals(1f, Waveform.level(3.0))
        assertEquals(1f, Waveform.levelOfAmplitude(32_767))
        assertEquals(0f, Waveform.levelOfAmplitude(0))
        assertEquals(0f, Waveform.levelOfAmplitude(-3))
        // 3277 is a tenth of full scale: -20 dB.
        assertEquals(0.6f, Waveform.levelOfAmplitude(3_277), 0.001f)
    }

    @Test
    fun encodeTakesEachShareLoudest() {
        val levels = List(640) { if (it % 10 == 3) 0.9f else 0.1f }
        assertEquals(List(64) { 90 }, Waveform.encode(levels))
        // A short word at the end still shows.
        val word = List(6_000) { if (it > 5_990) 1f else 0f }
        assertEquals(100, Waveform.encode(word).last())
        assertEquals(0, Waveform.encode(word).first())
    }

    @Test
    fun encodeStretchesAShortRecording() {
        val stretched = Waveform.encode(listOf(0f, 0.5f, 1f))
        assertEquals(64, stretched.size)
        assertEquals(listOf(0, 50, 100), stretched.distinct())
        assertEquals(emptyList<Int>(), Waveform.encode(emptyList()))
        assertEquals(listOf(100, 0), Waveform.encode(listOf(4f, -1f), points = 2))
    }

    @Test
    fun barsToDraw() {
        assertEquals(List(5) { Waveform.PLAIN }, Waveform.bars(null, 5))
        assertEquals(List(3) { Waveform.PLAIN }, Waveform.bars(emptyList(), 3))
        assertEquals(emptyList<Float>(), Waveform.bars(listOf(10), 0))
        assertBars(listOf(1f, half), Waveform.bars(listOf(0, 100, 50, 0), 2))
        assertBars(listOf(Waveform.FLOOR, Waveform.FLOOR), Waveform.bars(listOf(0, 0), 2))
        // More bars than levels: each level stands for several.
        assertEquals(6, Waveform.bars(listOf(0, 100, 0), 6).size)
        assertBars(listOf(Waveform.FLOOR, Waveform.FLOOR, 1f, 1f, Waveform.FLOOR, Waveform.FLOOR), Waveform.bars(listOf(0, 100, 0), 6))
        assertBars(listOf(1f), Waveform.bars(listOf(400), 1))
    }

    @Test
    fun liveShowsTheNewestAtTheEnd() {
        assertEquals(List(4) { Waveform.FLOOR }, Waveform.live(emptyList(), 4))
        assertBars(listOf(1f, half, 1f), Waveform.live(listOf(1f, 0f, 1f, 0.5f, 1f), 3))
        assertBars(listOf(Waveform.FLOOR, 1f), Waveform.live(listOf(1f), 2))
        assertEquals(emptyList<Float>(), Waveform.live(listOf(1f), 0))
    }
}
