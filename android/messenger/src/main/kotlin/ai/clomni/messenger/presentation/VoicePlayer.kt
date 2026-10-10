package ai.clomni.messenger.presentation

import java.io.File

/** The speaker as [VoicePlayer] uses it: Android's MediaPlayer in the SDK, a fake in tests. One file at a time. */
internal interface AudioOutput {
    /** What happens to the file [open]ed last; a callback for an earlier file never comes. */
    interface Listener {
        fun ready(durationMs: Long)
        fun failed()
        fun finished()

        /** Another app or a call took the sound: it is paused. */
        fun interrupted()
    }

    /** Opens [file], closing the one before it; [listener] hears when it can play. */
    fun open(file: File, listener: Listener)

    fun play(rate: Float)
    fun pause()
    fun seek(positionMs: Long)

    /** Changes the speed of what plays; a paused file keeps it for its next [play]. */
    fun setRate(rate: Float)

    val positionMs: Long

    /** Lets the file and the sound go. */
    fun close()

    /** [file]'s length without playing it, or null when it is not a recording the platform reads. */
    fun duration(file: File): Long?
}

/** Fetches a recording once, then answers from the cache; [done] runs on the UI thread, with null on a failure. */
internal fun interface VoiceFiles {
    fun fetch(url: String, done: (File?) -> Unit)
}

/**
 * Plays voice messages, one at a time: starting one pauses the other where it was. Each bubble reads its own [track];
 * the speed (1×, 1.5×, 2×) is one for all, the last one chosen, as in WhatsApp. A file comes from [files] (once, then
 * from the cache) or, for the user's own recording, from the disk. On the UI thread; the same as the iOS SDK's
 * VoicePlayer.
 */
internal class VoicePlayer(
    private val files: VoiceFiles,
    private val output: AudioOutput,
    private val scheduler: Scheduler,
) {
    enum class Phase { IDLE, LOADING, PLAYING, PAUSED, FAILED }

    /** [durationMs] is null until known: from the message, or from the file once it is here. */
    data class Track(val phase: Phase = Phase.IDLE, val positionMs: Long = 0, val durationMs: Long? = null) {
        /** How far it has played, 0–1. */
        val progress: Float
            get() = durationMs?.takeIf { it > 0 }?.let { (positionMs.toFloat() / it).coerceIn(0f, 1f) } ?: 0f
    }

    enum class Speed(val rate: Float, val label: String) {
        NORMAL(1f, "1×"),
        FAST(1.5f, "1.5×"),
        FASTEST(2f, "2×"),
        ;

        val next: Speed get() = entries[(ordinal + 1) % entries.size]
    }

    /** Where a recording is: the server's, fetched once; or a file on the device (being sent, or being reviewed). */
    sealed interface Source {
        data class Remote(val url: String) : Source

        data class Local(val file: File) : Source
    }

    var speed: Speed = Speed.NORMAL
        private set

    /** Called after any track or the speed changed. */
    var onChange: (() -> Unit)? = null

    private val tracks = HashMap<String, Track>()
    private val probed = HashSet<String>()

    /** The message open in [output]. */
    private var current: String? = null

    /** Bumped with each open: an answer for an earlier one is dropped. */
    private var generation = 0
    private var cancelTick: (() -> Unit)? = null

    fun track(id: String): Track = tracks[id] ?: Track()

    /** The play/pause button of message [id]; [knownDurationMs] is the message's own. */
    fun toggle(id: String, source: Source, knownDurationMs: Long?) {
        val track = track(id)
        if (id == current) {
            when (track.phase) {
                Phase.PLAYING -> return pauseCurrent()
                Phase.PAUSED -> {
                    output.play(speed.rate)
                    set(id, track.copy(phase = Phase.PLAYING))
                    return tick()
                }
                Phase.LOADING -> {
                    generation++
                    current = null
                    return set(id, track.copy(phase = Phase.IDLE))
                }
                else -> Unit
            }
        }
        leaveCurrent()
        val opening = ++generation
        current = id
        set(id, track.copy(phase = Phase.LOADING, durationMs = track.durationMs ?: knownDurationMs))
        when (source) {
            is Source.Local -> open(id, source.file, opening)
            is Source.Remote -> files.fetch(source.url) { file ->
                if (opening != generation) return@fetch
                if (file == null) fail(id) else open(id, file, opening)
            }
        }
    }

    /**
     * Moves message [id] to [fraction] of its length (a tap or a drag on its waveform): where it plays, or where it
     * starts next. Nothing for a length not known yet.
     */
    fun seek(id: String, fraction: Float, knownDurationMs: Long?) {
        val track = track(id)
        val duration = track.durationMs ?: knownDurationMs ?: return
        val position = (duration * fraction.coerceIn(0f, 1f)).toLong()
        if (id == current && (track.phase == Phase.PLAYING || track.phase == Phase.PAUSED)) output.seek(position)
        val phase = if (track.phase == Phase.IDLE || track.phase == Phase.FAILED) Phase.PAUSED else track.phase
        set(id, track.copy(phase = phase, positionMs = position, durationMs = duration))
    }

    /** 1× → 1.5× → 2× → 1×. */
    fun cycleSpeed() {
        speed = speed.next
        if (current?.let(::track)?.phase == Phase.PLAYING) output.setRate(speed.rate)
        onChange?.invoke()
    }

    /**
     * Learns the length of a recording whose message does not say it (the panel's MP3), by fetching the file; asked
     * once per message.
     */
    fun prefetch(id: String, url: String) {
        if (track(id).durationMs != null || !probed.add(id)) return
        files.fetch(url) { file ->
            val duration = file?.let(output::duration) ?: return@fetch
            if (track(id).durationMs == null) set(id, track(id).copy(durationMs = duration))
        }
    }

    /** A recording starts, or the screen goes: what plays pauses where it is. */
    fun pause() = pauseCurrent()

    /** The screen is gone: the file and the sound are let go. */
    fun release() {
        pauseCurrent()
        generation++
        current = null
        output.close()
    }

    private fun open(id: String, file: File, opening: Int) {
        output.open(
            file,
            object : AudioOutput.Listener {
                override fun ready(durationMs: Long) {
                    if (opening != generation) return
                    val track = track(id)
                    val duration = durationMs.takeIf { it > 0 } ?: track.durationMs
                    val start = track.positionMs.takeIf { duration == null || it < duration } ?: 0
                    if (start > 0) output.seek(start)
                    output.play(speed.rate)
                    set(id, track.copy(phase = Phase.PLAYING, positionMs = start, durationMs = duration))
                    tick()
                }

                override fun failed() {
                    if (opening == generation) fail(id)
                }

                override fun finished() {
                    if (opening != generation) return
                    stopTicking()
                    current = null
                    set(id, track(id).copy(phase = Phase.IDLE, positionMs = 0))
                }

                override fun interrupted() {
                    if (opening == generation) pauseCurrent()
                }
            },
        )
    }

    private fun fail(id: String) {
        stopTicking()
        if (current == id) current = null
        set(id, track(id).copy(phase = Phase.FAILED))
    }

    /** Another message is about to play: this one pauses, or stops loading. */
    private fun leaveCurrent() {
        val id = current ?: return
        if (track(id).phase == Phase.LOADING) set(id, track(id).copy(phase = Phase.IDLE)) else pauseCurrent()
    }

    private fun pauseCurrent() {
        val id = current ?: return
        val track = track(id)
        if (track.phase != Phase.PLAYING) return
        output.pause()
        stopTicking()
        set(id, track.copy(phase = Phase.PAUSED, positionMs = output.positionMs))
    }

    /** While one plays, its position every [TICK_MS]. */
    private fun tick() {
        stopTicking()
        val id = current ?: return
        val track = track(id)
        if (track.phase != Phase.PLAYING) return
        set(id, track.copy(positionMs = output.positionMs.coerceAtMost(track.durationMs ?: Long.MAX_VALUE)))
        cancelTick = scheduler.after(TICK_MS, ::tick)
    }

    private fun stopTicking() {
        cancelTick?.invoke()
        cancelTick = null
    }

    private fun set(id: String, track: Track) {
        tracks[id] = track
        onChange?.invoke()
    }

    companion object {
        /** The waveform fills smoothly: 20 times a second. */
        const val TICK_MS = 50L
    }
}
