package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatSound
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool

/**
 * One short sound (Universfield, Pixabay Content License): at full volume for a message that arrives while the
 * conversation is open, at 40% for one the user sends (DESIGN-PASS-3 B4). It plays as UI sounds (sonification): silent and vibrate mode mute them, and they never take audio
 * focus, so music keeps playing. Off when the panel says `sounds: false` or the app calls `setSoundsEnabled(false)`.
 */
internal object MessageSounds {
    /** `Clomni.setSoundsEnabled`. */
    @Volatile var appEnabled: Boolean = true

    private const val SENT_VOLUME = 0.4f

    private var pool: SoundPool? = null
    private var id = 0

    /** Loads the sound (50 KB) the first time a conversation opens; on the UI thread. */
    fun prepare(context: Context) {
        if (pool != null) return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build().also {
            id = it.load(context.applicationContext, R.raw.clomni_message, 1)
        }
    }

    fun play(context: Context, sound: ChatSound) {
        if (!appEnabled) return
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audio != null && audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val volume = if (sound == ChatSound.SENT) SENT_VOLUME else 1f
        pool?.play(id, volume, volume, 1, 0, 1f)
    }
}
