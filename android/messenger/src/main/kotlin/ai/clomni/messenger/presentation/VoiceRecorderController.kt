package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.VoiceRecording.Effect
import java.io.File

/** The microphone as [VoiceRecorderController] uses it: Android's MediaRecorder in the SDK, a fake in tests. */
internal interface MicInput {
    /** Starts recording AAC (m4a) into [file]; false when the microphone cannot be had. */
    fun start(file: File): Boolean

    /** The loudness since the last call, 0–1. */
    fun level(): Float

    /** Stops; the recording's length in ms, or null when nothing usable was written (the file is then gone). */
    fun stop(): Long?

    /** Stops and deletes what was written. */
    fun cancel()
}

/** A finished recording: the m4a, its length and its waveform (0–100 each). */
internal data class VoiceClip(val file: File, val durationMs: Long, val waveform: List<Int>)

/**
 * Runs [VoiceRecording] against the microphone: starts and stops it, reads the clock and the loudness every
 * [TICK_MS] for the timer and the live waveform, and hands a finished recording to [send]. The view reads [state],
 * [levels], [hint] and [review] after each [onChange], and drops the microphone into the bin each time [discards]
 * grows. On the UI thread, like ChatController; the same as the iOS SDK's VoiceRecorderController.
 */
internal class VoiceRecorderController(
    private val mic: MicInput,
    private val permission: () -> VoiceRecording.Permission,
    /** Asks the system for the microphone; the user presses again once it is given. */
    private val askPermission: () -> Unit,
    /** Where the next recording goes (the cache). */
    private val newFile: () -> File,
    private val scheduler: Scheduler,
    private val now: () -> Long,
    maxMs: Long,
    private val send: (VoiceClip) -> Unit,
    private val feedback: (Feedback) -> Unit = {},
) {
    /**
     * What the capsule over the button says: hold longer; the microphone is refused (with the way to the settings); the
     * recording reached the limit and stopped.
     */
    enum class Hint { HOLD, DENIED, LIMIT }

    /** The haptic ticks: recording started, locked, thrown away. */
    enum class Feedback { START, LOCK, CANCEL }

    private val machine = VoiceRecording(maxMs)

    /** Called after anything the view shows changed. */
    var onChange: (() -> Unit)? = null

    val state: VoiceRecording.State get() = machine.state

    /** The loudness so far, a level a tick. */
    val levels: List<Float> get() = machine.levels

    var hint: Hint? = null
        private set

    /** Stopped and waiting: what Send sends and the preview plays. */
    var review: VoiceClip? = null
        private set

    /** Grows with each recording thrown away by a slide or Delete: the view's cue for the bin. */
    var discards: Int = 0
        private set

    private var file: File? = null
    private var recording = false
    private var startedAt = 0L
    private var cancelTick: (() -> Unit)? = null
    private var cancelHint: (() -> Unit)? = null

    fun press() = run(machine.press(permission()))

    fun pressLocked() = run(machine.pressLocked(permission()))

    /** [dx], [dy]: dp from where the finger went down. */
    fun drag(dx: Float, dy: Float) = run(machine.drag(dx, dy))

    fun release() = run(machine.release())

    fun stop() = run(machine.stop())

    fun delete() = run(machine.delete())

    fun send() = run(machine.send())

    fun dismissHint() {
        setHint(null)
        onChange?.invoke()
    }

    /** The screen goes away: a recording in progress or waiting is thrown away. */
    fun close() {
        machine.fail()
        discard(animated = false)
        setHint(null)
    }

    private fun run(effects: List<Effect>) {
        effects.forEach(::apply)
        onChange?.invoke()
    }

    private fun apply(effect: Effect) {
        when (effect) {
            Effect.Start -> start()
            is Effect.Send -> finish(effect.waveform)
            Effect.Stop -> stopForReview()
            is Effect.Discard -> discard(effect.animated)
            Effect.HoldHint -> setHint(Hint.HOLD)
            Effect.Locked -> feedback(Feedback.LOCK)
            Effect.AskPermission -> askPermission()
            Effect.PermissionDenied -> setHint(Hint.DENIED)
        }
    }

    private fun start() {
        setHint(null)
        val target = newFile()
        if (!mic.start(target)) {
            machine.fail()
            return
        }
        file = target
        recording = true
        startedAt = now()
        feedback(Feedback.START)
        cancelTick = scheduler.after(TICK_MS, ::tick)
    }

    private fun tick() {
        if (!recording) return
        val effects = machine.tick(now() - startedAt, mic.level())
        if (Effect.Stop in effects) setHint(Hint.LIMIT)
        run(effects)
        if (recording) cancelTick = scheduler.after(TICK_MS, ::tick)
    }

    /** The recording's length, or null when the recorder had nothing. */
    private fun stopMic(): Long? {
        cancelTick?.invoke()
        cancelTick = null
        recording = false
        return mic.stop()
    }

    private fun finish(waveform: List<Int>) {
        val clip = if (recording) {
            val duration = stopMic()
            val target = file
            if (duration == null || target == null) null else VoiceClip(target, duration, waveform)
        } else {
            review?.copy(waveform = waveform)
        }
        file = null
        review = null
        clip?.let(send)
    }

    private fun stopForReview() {
        if (!recording) return
        val duration = stopMic()
        val target = file
        if (duration == null || target == null) {
            machine.fail()
            file = null
            return
        }
        review = VoiceClip(target, duration, machine.waveform())
    }

    private fun discard(animated: Boolean) {
        if (recording) {
            cancelTick?.invoke()
            cancelTick = null
            recording = false
            mic.cancel()
        } else {
            review?.file?.delete()
        }
        file = null
        review = null
        if (animated) {
            discards++
            feedback(Feedback.CANCEL)
        }
    }

    private fun setHint(next: Hint?) {
        cancelHint?.invoke()
        cancelHint = null
        hint = next
        if (next != null) {
            cancelHint = scheduler.after(if (next == Hint.DENIED) DENIED_HINT_MS else HOLD_HINT_MS) {
                hint = null
                onChange?.invoke()
            }
        }
    }

    companion object {
        /** 20 a second: the timer and the live waveform. */
        const val TICK_MS = 50L
        const val HOLD_HINT_MS = 2_000L
        const val DENIED_HINT_MS = 6_000L
    }
}
