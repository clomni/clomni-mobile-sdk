package ai.clomni.messenger.ui

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Pulling the messenger sheet down (DESIGN-PASS-3 A8, C3): [offset] is how far it is, in px; [fraction] of its height.
 * Released past a third, or flicked down, it closes ([dismiss]); otherwise it springs back. The offset is plain state,
 * set on each move of the finger, so the sheet follows it in the same frame.
 */
internal class SheetDrag(private val scope: CoroutineScope, private val dismiss: () -> Unit) {
    var offset by mutableFloatStateOf(0f)
        private set
    var height = 1f
    private var back: Job? = null

    val fraction: Float get() = (offset / height).coerceIn(0f, 1f)

    fun dragBy(delta: Float) {
        back?.cancel()
        offset = (offset + delta).coerceIn(0f, height)
    }

    /** With the system's animations off it closes or goes back at once. */
    var still = false

    /** Let go: on a spring that starts at the finger's speed (M1), down and closed, or back up. */
    fun settle(velocity: Float) {
        if (offset <= 0f) return
        val closes = offset > height / 3 || velocity > FLICK
        if (still) {
            if (closes) dismiss() else offset = 0f
            return
        }
        back = scope.launch {
            if (closes) {
                animate(offset, height, velocity, spring(stiffness = 400f)) { value, _ -> offset = value }
                dismiss()
            } else {
                animate(offset, 0f, velocity, Motion.sheet()) { value, _ -> offset = value.coerceAtLeast(0f) }
            }
        }
    }

    private companion object {
        /** px/s: a flick down closes the sheet however little it moved. */
        const val FLICK = 1500f
    }
}

@Composable
internal fun rememberSheetDrag(dismiss: () -> Unit): SheetDrag {
    val scope = rememberCoroutineScope()
    return remember { SheetDrag(scope, dismiss) }
}

/**
 * The sheet follows the finger from its top only (C3): a drag that starts within [zone] of the top (the handle's 24 dp
 * and the header). A list's scroll never moves it, not even past the list's top. Once such a drag has gone a touch slop
 * down (or back up while the sheet is pulled) more than sideways it is the sheet's: taken before the children see it,
 * so a button under the finger is not pressed and nothing under the header scrolls. On the sheet's frame, which does
 * not move: the sheet inside it is offset by [SheetDrag.offset].
 */
internal fun Modifier.sheetDrag(drag: SheetDrag, zone: Dp = 24.dp + 64.dp): Modifier =
    onSizeChanged { drag.height = it.height.toFloat().coerceAtLeast(1f) }
        .pointerInput(drag) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                if (down.position.y - drag.offset > zone.toPx()) return@awaitEachGesture
                val tracker = VelocityTracker()
                tracker.addPointerInputChange(down)
                val slop = viewConfiguration.touchSlop
                var moved = Offset.Zero
                while (true) {
                    val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id }
                    if (change == null || !change.pressed || change.isConsumed) return@awaitEachGesture
                    tracker.addPointerInputChange(change)
                    moved += change.position - change.previousPosition
                    if (abs(moved.x) <= slop && abs(moved.y) <= slop) continue
                    val ours = abs(moved.y) > abs(moved.x) && (moved.y > 0f || drag.offset > 0f)
                    if (!ours) return@awaitEachGesture
                    change.consume()
                    drag.dragBy(moved.y - if (moved.y > 0f) slop else -slop)
                    break
                }
                while (true) {
                    val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
                    tracker.addPointerInputChange(change)
                    change.consume()
                    if (!change.pressed) break
                    drag.dragBy(change.position.y - change.previousPosition.y)
                }
                drag.settle(tracker.calculateVelocity().y)
            }
        }
