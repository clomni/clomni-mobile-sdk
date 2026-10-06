package ai.clomni.messenger.ui

import android.content.Context
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp

/**
 * Brief 8·7.6: with the system's animations off ("Remove animations", ANIMATOR_DURATION_SCALE 0) nothing moves,
 * things only fade: new messages, the transcript's scroll, the screens, and the messenger opening and closing.
 *
 * DESIGN-PASS-3 M1–M10 ("Intercom kimi"): everything moves on a spring or on Material's emphasized easing, nothing
 * jumps; the same numbers on iOS.
 */
internal object Motion {
    fun reduced(context: Context): Boolean = runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)

    /** Material 3's emphasized decelerate and accelerate. */
    val EmphasizedDecelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
    val EmphasizedAccelerate = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)

    /** M1: the sheet, damping 0.86, stiffness 400. */
    fun <T> sheet(visibilityThreshold: T? = null) = spring(dampingRatio = 0.86f, stiffness = 400f, visibilityThreshold = visibilityThreshold)

    /** The offline capsule's 200 ms spring (CM-077): damping 0.86, stiffness 1000 (iOS: response 0.2). */
    fun <T> capsule(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.86f, stiffness = 1000f)

    /** M6: a press, and its release. */
    fun <T> press(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.6f, stiffness = 800f)

    /** How a new item of the transcript comes in (M3, M4). */
    enum class Arrival {
        /** An incoming bubble: 8 up, 0.97 → 1, fading in, 200 ms. */
        INCOMING,

        /** The user's own: out of the composer, 12 up, fading in, 180 ms. */
        OUTGOING,

        /** The typing bubble: fade and scale. */
        TYPING,

        /** A time or system line: a fade. */
        FADE,
    }
}

/** True while the item being drawn is new in the transcript, not one there when the screen opened (M3, M5). */
internal val LocalArriving = compositionLocalOf { false }

/** [arrival] when [animate]; nothing for null. */
@Composable
internal fun Modifier.arriving(animate: Boolean, arrival: Motion.Arrival?): Modifier = when (arrival) {
    null -> this
    Motion.Arrival.INCOMING -> entrance(animate, 8f, 0.97f, 200)
    Motion.Arrival.OUTGOING -> entrance(animate, 12f, 1f, 180)
    Motion.Arrival.TYPING -> entrance(animate, 4f, 0.9f, 200)
    Motion.Arrival.FADE -> entrance(animate, 0f, 1f, 200)
}

/**
 * When [animate]: after [delay] ms it rises [rise] dp, grows from [from] and fades in over [duration] ms, on the
 * emphasized easing. With the system's animations off it only fades (M10); in previews it is simply there.
 */
@Composable
internal fun Modifier.entrance(animate: Boolean, rise: Float, from: Float, duration: Int, delay: Int = 0): Modifier {
    if (!animate || LocalInspectionMode.current) return this
    val still = reduceMotion()
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) { progress.animateTo(1f, tween(if (still) 150 else duration, delay, Motion.EmphasizedDecelerate)) }
    val distance = with(LocalDensity.current) { rise.dp.toPx() }
    return graphicsLayer {
        val p = progress.value
        alpha = p
        if (!still) {
            translationY = (1f - p) * distance
            scaleX = from + (1f - from) * p
            scaleY = scaleX
        }
    }
}
