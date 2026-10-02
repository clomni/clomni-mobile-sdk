package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import android.content.Context
import android.provider.Settings

/**
 * Brief 8·7.6: with the system's animations off ("Remove animations", ANIMATOR_DURATION_SCALE 0) nothing moves,
 * things only fade: new messages, the transcript's scroll, and the messenger opening and closing.
 */
internal object Motion {
    fun reduced(context: Context): Boolean = runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)

    /** The messenger coming up over the app: slides up, or fades in. */
    fun open(context: Context): Int = if (reduced(context)) R.anim.clomni_fade_in else R.anim.clomni_slide_up

    /** And going: slides down, or fades out. */
    fun close(context: Context): Int = if (reduced(context)) R.anim.clomni_fade_out else R.anim.clomni_slide_down
}
