package ai.clomni.messenger.presentation

import kotlin.math.max
import kotlin.math.min

/**
 * What the microphone button is doing, WhatsApp's way. Held, it records; let go, it sends. Slid left past
 * [CANCEL_DP] it throws the recording away; slid up past [LOCK_DP] it locks, and the hand can go: then Stop, Delete
 * and Send, and after Stop the recording can be heard before it goes. A press shorter than [MIN_MS] sends nothing and
 * asks to hold ("Yazmaq üçün basıb saxlayın"). At [maxMs] (the config's voice_seconds) it stops by itself and waits
 * for Send or Delete.
 *
 * Only the rules: the view feeds it touches and the recorder's ticks and carries out what it answers ([Effect]). The
 * same machine as the iOS SDK's VoiceRecording.
 */
internal class VoiceRecording(private val maxMs: Long) {

    sealed interface State {
        data object Idle : State

        /** The finger is down: [cancel] and [lock] are how far it has gone towards each, 0–1. */
        data class Holding(val elapsedMs: Long, val cancel: Float, val lock: Float) : State

        /** Recording with no hand on the button: Stop, Delete, Send. */
        data class Locked(val elapsedMs: Long) : State

        /** Stopped: heard before it goes, or deleted. */
        data class Review(val durationMs: Long) : State
    }

    sealed interface Effect {
        /** Start the microphone (and the light haptic tick). */
        data object Start : Effect

        /** Stop the microphone if it runs, and send the recording with [waveform]. */
        data class Send(val waveform: List<Int>) : Effect

        /** Stop the microphone and keep the recording for listening. */
        data object Stop : Effect

        /** Stop the microphone if it runs and delete the recording; [animated]: the microphone falls into the bin. */
        data class Discard(val animated: Boolean) : Effect

        /** The press was too short: "Yazmaq üçün basıb saxlayın". */
        data object HoldHint : Effect

        /** The lock closed: a haptic tick, and TalkBack says "Yazma kilidləndi". */
        data object Locked : Effect

        /** The first press: ask for the microphone; the next press records. */
        data object AskPermission : Effect

        /** Refused for good: say why nothing happens, with the way to the settings. */
        data object PermissionDenied : Effect
    }

    enum class Permission { GRANTED, UNDECIDED, DENIED }

    var state: State = State.Idle
        private set

    /** The loudness so far, 0–1 a tick: the live waveform, and the message's once it goes. */
    val levels: List<Float> get() = recorded

    private val recorded = ArrayList<Float>()

    val isActive: Boolean get() = state != State.Idle

    /** The finger went down on the microphone. */
    fun press(permission: Permission): List<Effect> {
        if (state != State.Idle) return emptyList()
        return when (permission) {
            Permission.GRANTED -> {
                recorded.clear()
                state = State.Holding(0, 0f, 0f)
                listOf(Effect.Start)
            }
            Permission.UNDECIDED -> listOf(Effect.AskPermission)
            Permission.DENIED -> listOf(Effect.PermissionDenied)
        }
    }

    /** TalkBack's double tap: there is no holding with it, so it records locked, with Stop, Delete and Send. */
    fun pressLocked(permission: Permission): List<Effect> {
        val effects = press(permission)
        if (state is State.Holding) state = State.Locked(0)
        return effects
    }

    /** The finger moved [dx], [dy] dp from where it went down; left and up are negative. */
    fun drag(dx: Float, dy: Float): List<Effect> {
        val holding = state as? State.Holding ?: return emptyList()
        val cancel = toward(-dx, CANCEL_DP)
        val lock = toward(-dy, LOCK_DP)
        return when {
            cancel >= 1f -> {
                state = State.Idle
                listOf(Effect.Discard(animated = true))
            }
            lock >= 1f -> {
                state = State.Locked(holding.elapsedMs)
                listOf(Effect.Locked)
            }
            else -> {
                state = holding.copy(cancel = cancel, lock = lock)
                emptyList()
            }
        }
    }

    /** The finger came up: sent, or too short to be a message. */
    fun release(): List<Effect> {
        val holding = state as? State.Holding ?: return emptyList()
        state = State.Idle
        return if (holding.elapsedMs < MIN_MS) listOf(Effect.Discard(animated = false), Effect.HoldHint) else listOf(Effect.Send(waveform()))
    }

    /**
     * The time since the finger went down, and the loudness since the last tick: null while the microphone is still
     * starting and has recorded nothing (CM-131).
     */
    fun tick(elapsedMs: Long, level: Float?): List<Effect> {
        state = when (val current = state) {
            is State.Holding -> current.copy(elapsedMs = elapsedMs)
            is State.Locked -> current.copy(elapsedMs = elapsedMs)
            else -> return emptyList()
        }
        if (level != null) recorded += level.coerceIn(0f, 1f)
        if (elapsedMs < maxMs) return emptyList()
        state = State.Review(elapsedMs)
        return listOf(Effect.Stop)
    }

    /** "Dayandır" while locked. */
    fun stop(): List<Effect> {
        val locked = state as? State.Locked ?: return emptyList()
        state = State.Review(locked.elapsedMs)
        return listOf(Effect.Stop)
    }

    /** "Sil" while locked or listening. */
    fun delete(): List<Effect> {
        if (state !is State.Locked && state !is State.Review) return emptyList()
        state = State.Idle
        return listOf(Effect.Discard(animated = true))
    }

    /** "Göndər" while locked or listening. */
    fun send(): List<Effect> {
        if (state !is State.Locked && state !is State.Review) return emptyList()
        state = State.Idle
        return listOf(Effect.Send(waveform()))
    }

    /** The recorder could not start or lost the microphone: nothing goes. */
    fun fail(): List<Effect> {
        if (state == State.Idle) return emptyList()
        state = State.Idle
        return listOf(Effect.Discard(animated = false))
    }

    /** How far [distance] went towards [goal], 0–1 (Math.max: a finger that did not move is 0, not -0). */
    private fun toward(distance: Float, goal: Float): Float = max(0f, min(1f, distance / goal))

    /** What goes with the message: [Waveform.POINTS] levels of 0–100. */
    fun waveform(): List<Int> = Waveform.encode(recorded)

    companion object {
        /** Shorter is a slip of the finger, not a message. */
        const val MIN_MS = 700L

        /** How far left cancels. */
        const val CANCEL_DP = 120f

        /** How far up locks. */
        const val LOCK_DP = 90f
    }
}
