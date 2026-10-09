package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.MessageContent
import java.io.File

/**
 * A voice message's bubble, decided here so the view only draws it: the play button, the waveform filling as it
 * plays, the length (what is left while it plays), the speed. The same as the iOS SDK's VoiceNote.
 */
internal data class VoiceNote(
    /** The player's key: the message's id, or the client id while it is on its way. */
    val id: String,
    val source: VoicePlayer.Source,
    /** The message's own length; null until the file says it. */
    val durationMs: Long?,
    /** 0–100 each, or null: plain bars. */
    val waveform: List<Int>?,
    val outgoing: Boolean,
    /** The user's recording is still uploading: a ring turns inside the play button. */
    val sending: Boolean = false,
) {
    /** The time under the waveform: what is left while it plays or waits half-heard, otherwise its length. */
    fun time(track: VoicePlayer.Track): String {
        val duration = track.durationMs ?: durationMs
        val started = track.phase == VoicePlayer.Phase.PLAYING || (track.phase == VoicePlayer.Phase.PAUSED && track.positionMs > 0)
        return when {
            duration == null -> VoiceTime.clock(track.positionMs)
            started -> VoiceTime.remaining(duration - track.positionMs)
            else -> VoiceTime.length(duration)
        }
    }

    /** TalkBack's reading of the bubble: "Səsli mesaj, 0:14". */
    fun accessibilityLabel(track: VoicePlayer.Track, strings: ClomniStrings): String {
        val duration = track.durationMs ?: durationMs ?: return strings[Key.VOICE_MESSAGE]
        return "${strings[Key.VOICE_MESSAGE]}, ${VoiceTime.length(duration)}"
    }

    companion object {
        /** A message from the server: played from its file, fetched once. */
        fun of(id: String, audio: MessageContent.Audio, outgoing: Boolean) =
            VoiceNote(id, VoicePlayer.Source.Remote(audio.url), audio.durationMs, audio.waveform, outgoing)

        /** The user's own on its way (uploading, or waiting for the connection): played from the recording itself. */
        fun sending(clientId: String, file: File, durationMs: Long?, waveform: List<Int>?, uploading: Boolean) =
            VoiceNote(clientId, VoicePlayer.Source.Local(file), durationMs, waveform, outgoing = true, sending = uploading)
    }
}

/** Times of voice messages: "0:07", "1:05", "12:00". */
internal object VoiceTime {
    /** A clock that runs (the recorder's timer, a position): whole seconds gone. */
    fun clock(ms: Long): String = format(maxOf(0, ms) / 1000)

    /** A length: the nearest second, at least one. */
    fun length(ms: Long): String = format(maxOf(1, (ms + 500) / 1000))

    /** What is left: a part of a second still counts, so it reads 0:00 only at the end. */
    fun remaining(ms: Long): String = format(maxOf(0, ms + 999) / 1000)

    private fun format(seconds: Long): String = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
}
