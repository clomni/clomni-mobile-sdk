package ai.clomni.messenger.presentation

import kotlin.math.log10
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * A voice message's waveform: the loudness the recorder measured, as the protocol carries it (audio.waveform: whole
 * numbers of 0–100, [POINTS] of them from the SDKs) and as the bubble draws it (bar heights of 0–1). The same numbers
 * as the iOS SDK's Waveform.
 */
internal object Waveform {
    /** What an SDK sends with a voice message. */
    const val POINTS = 64

    /** The quietest bar: silence still shows as a dot, as in WhatsApp. */
    const val FLOOR = 0.12f

    /** The bars of a recording without a waveform (an operator's MP3): plain, all one low height. */
    const val PLAIN = 0.3f

    /** Loudness under this many dB below full scale is silence. */
    private const val RANGE_DB = 50.0

    /** A level of 0–1 from loudness in dBFS: -50 dB and below is 0, 0 dB is 1. */
    fun level(decibels: Double): Float = ((decibels + RANGE_DB) / RANGE_DB).coerceIn(0.0, 1.0).toFloat()

    /** MediaRecorder's getMaxAmplitude (0–32767, the loudest since the last call) as a level. */
    fun levelOfAmplitude(amplitude: Int): Float = if (amplitude <= 0) 0f else level(20 * log10(amplitude / 32767.0))

    /**
     * [levels] (0–1, one per tick of the recorder, in order) as [points] whole numbers of 0–100: each the loudest of
     * its share of the ticks, so a short word still shows; fewer ticks than points are stretched. Empty for none.
     */
    fun encode(levels: List<Float>, points: Int = POINTS): List<Int> {
        if (levels.isEmpty()) return emptyList()
        return List(points) { index ->
            val (from, to) = share(index, points, levels.size)
            (levels.subList(from, to).max().coerceIn(0f, 1f) * 100).roundToInt()
        }
    }

    /**
     * [count] bar heights of 0–1 for [waveform] (0–100 each), at least [FLOOR]; without one, [count] plain bars of
     * [PLAIN].
     */
    fun bars(waveform: List<Int>?, count: Int): List<Float> {
        if (count <= 0) return emptyList()
        if (waveform.isNullOrEmpty()) return List(count) { PLAIN }
        return List(count) { index ->
            val (from, to) = share(index, count, waveform.size)
            FLOOR + (1 - FLOOR) * waveform.subList(from, to).max().coerceIn(0, 100) / 100f
        }
    }

    /**
     * The live waveform while recording: the newest [count] levels as bar heights, the newest at the end; quieter
     * than [FLOOR] before anything was heard.
     */
    fun live(levels: List<Float>, count: Int): List<Float> {
        if (count <= 0) return emptyList()
        val recent = levels.takeLast(count)
        return List(count - recent.size) { FLOOR } + recent.map { FLOOR + (1 - FLOOR) * it.coerceIn(0f, 1f) }
    }

    /** The share of [size] items bar [index] of [count] stands for: at least one. */
    private fun share(index: Int, count: Int, size: Int): Pair<Int, Int> {
        val from = (index.toLong() * size / count).toInt().coerceAtMost(size - 1)
        val to = max(from + 1, ((index + 1).toLong() * size / count).toInt())
        return from to to
    }
}
