package ai.clomni.messenger.ui

import android.content.Context
import android.provider.Settings

/**
 * Brief 8·7.6: with the system's animations off ("Remove animations", ANIMATOR_DURATION_SCALE 0) nothing moves,
 * things only fade: new messages, the transcript's scroll, the screens, and the messenger opening and closing.
 */
internal object Motion {
    fun reduced(context: Context): Boolean = runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)
}
