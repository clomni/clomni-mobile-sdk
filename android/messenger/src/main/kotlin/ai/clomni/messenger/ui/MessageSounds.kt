package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatSound
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool

/**
 * The web widget's two short sounds: a ding for a message that arrives while the conversation is open, a ping for one
 * the user sends. They play as UI sounds (sonification): silent and vibrate mode mute them, and they never take audio
 * focus, so music keeps playing. Off when the panel says `sounds: false` or the app calls `setSoundsEnabled(false)`.
 */
internal object MessageSounds {
    /** `Clomni.setSoundsEnabled`. */
    @Volatile var appEnabled: Boolean = true

    private var pool: SoundPool? = null
    private val ids = IntArray(2)

    /** Loads both sounds (a few KB) the first time a conversation opens; on the UI thread. */
    fun prepare(context: Context) {
        if (pool != null) return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build().also {
            val app = context.applicationContext
            ids[ChatSound.INCOMING.ordinal] = it.load(app, R.raw.clomni_ding, 1)
            ids[ChatSound.SENT.ordinal] = it.load(app, R.raw.clomni_ping, 1)
        }
    }

    fun play(context: Context, sound: ChatSound) {
        if (!appEnabled) return
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audio != null && audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        pool?.play(ids[sound.ordinal], 1f, 1f, 1, 0, 1f)
    }
}
