package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.LoadingGate
import ai.clomni.messenger.presentation.RgbColor
import android.os.SystemClock
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.NonRestartableComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * The platform's indeterminate circular indicator, as Material 3 draws it (a turning arc that grows and shrinks): 24 dp,
 * a 2.5 dp line in [color] (the brand's; grey before any config). TalkBack reads [label] ("Yüklənir"). Drawn here
 * rather than taken from the Material 3 library, which the SDK does not depend on.
 */
@Composable
internal fun Spinner(color: RgbColor, label: String, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    val turning = rememberInfiniteTransition(label = "spinner")
    val rotation by turning.animateFloat(0f, 360f, infiniteRepeatable(tween(1332, easing = LinearEasing)), label = "rotation")
    val sweep by turning.animateFloat(20f, 280f, infiniteRepeatable(tween(666), RepeatMode.Reverse), label = "sweep")
    // Screenshots catch one frame: the arc at its longest, standing still.
    val still = LocalInspectionMode.current
    Canvas(modifier.size(size).semantics { contentDescription = label }) {
        val stroke = 2.5.dp.toPx()
        drawArc(
            color.color,
            startAngle = if (still) -90f else rotation - 90f,
            sweepAngle = if (still) 280f else sweep,
            useCenter = false,
            topLeft = androidx.compose.ui.geometry.Offset(stroke / 2, stroke / 2),
            size = androidx.compose.ui.geometry.Size(this.size.width - stroke, this.size.height - stroke),
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}

/** [Spinner] while [loading], through [LoadingGate]: after 150 ms, for at least 400. Previews show it at once. */
@Composable
internal fun LoadingSpinner(loading: Boolean, color: RgbColor, label: String, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    if (LocalInspectionMode.current) {
        if (loading) Spinner(color, label, modifier, size)
        return
    }
    val gate = remember { LoadingGate() }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(loading) {
        while (true) {
            shown = gate.visible(loading, SystemClock.uptimeMillis())
            val next = gate.nextChange(loading) ?: break
            delay((next - SystemClock.uptimeMillis()).coerceAtLeast(1))
        }
    }
    if (shown) Spinner(color, label, modifier, size)
}

/** Contract 1.0.7b §5.1: the least time a screen that opens shows its spinner. */
internal const val OPENING_MS = 350L

/**
 * How a screen opens (contract 1.0.7b §5.1): the one before is gone at once; in its place this screen's [background]
 * and the brand's spinner in the middle, for at least [OPENING_MS] and until [ready]; then the page fades in over
 * 150 ms (at once with the system's animations off). Two screens are never drawn over each other.
 *
 * Every page of [pages] stays composed and keeps its state; only [shown], once open, is placed: the others are not
 * drawn, touched or read out. A change of [shown] opens it again (a tab: where it was, after the spinner). The first
 * page opens with the spinner only when [enter] (a screen pushed, not one gone back to). A screen of one page passes
 * [ONE_PAGE] and [Unit].
 */
@Composable
@NonRestartableComposable
internal fun <K : Any> OpeningPages(
    pages: List<K>,
    shown: K,
    ready: Boolean,
    enter: Boolean,
    background: Color,
    theme: ClomniTheme,
    label: String,
    page: @Composable (K) -> Unit,
) {
    val still = reduceMotion()
    // The page still opening, null once open; set while composing, so a new page is never placed for a frame first.
    var opening by remember { mutableStateOf(if (enter) shown else null) }
    // The page whose 350 ms are over.
    var waited by remember { mutableStateOf<Any?>(null) }
    val last = remember { arrayOf<Any>(shown) }
    if (last[0] != shown) {
        last[0] = shown
        opening = shown
        waited = null
    }
    val fade = remember { Animatable(1f) }
    LaunchedEffect(opening) {
        val opened = opening ?: return@LaunchedEffect
        // With the system's animations off the page simply comes: it never fades.
        if (!still) fade.snapTo(0f)
        delay(OPENING_MS)
        waited = opened
    }
    if (opening != null && waited == opening && ready) opening = null
    LaunchedEffect(opening == null) {
        if (opening == null) fade.animateTo(1f, tween(150))
    }
    Layout(
        content = {
            for (key in pages) key(key) { Box(Modifier.layoutId(key).graphicsLayer { alpha = fade.value }) { page(key) } }
            if (opening != null) Spinner(theme.colors.primary, label, size = 40.dp)
        },
        modifier = Modifier.fillMaxSize().background(background),
    ) { measurables, constraints ->
        // Read here: a change of page, or the end of its spinner, lays it out again by itself.
        val waiting = opening != null
        val child = measurables.firstOrNull { if (waiting) it.layoutId == null else it.layoutId == last[0] }
            ?.measure(if (waiting) constraints.copy(minWidth = 0, minHeight = 0) else constraints)
        layout(constraints.maxWidth, constraints.maxHeight) {
            child?.place((constraints.maxWidth - child.width) / 2, (constraints.maxHeight - child.height) / 2)
        }
    }
}

/** The pages of a screen of one page ([OpeningPages]). */
internal val ONE_PAGE = listOf(Unit)
