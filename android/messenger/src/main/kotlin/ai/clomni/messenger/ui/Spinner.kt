package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.LoadingGate
import ai.clomni.messenger.presentation.RgbColor
import android.os.SystemClock
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
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

/** [Spinner] while [loading], through [LoadingGate]: after 300 ms, for at least 400. Previews show it at once. */
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
