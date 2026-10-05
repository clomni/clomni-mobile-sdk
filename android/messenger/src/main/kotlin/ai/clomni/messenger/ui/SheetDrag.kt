package ai.clomni.messenger.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitVerticalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.verticalDrag
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Pulling the messenger sheet down (DESIGN-PASS-3 A8): [offset] is how far it is, in px; [fraction] of its height.
 * Released past a third, or flicked down, it closes ([dismiss]); otherwise it springs back.
 */
internal class SheetDrag(private val scope: CoroutineScope, private val dismiss: () -> Unit) {
    val offset = Animatable(0f)
    var height = 1f

    val fraction: Float get() = (offset.value / height).coerceIn(0f, 1f)

    fun dragBy(delta: Float) {
        scope.launch { offset.snapTo((offset.value + delta).coerceIn(0f, height)) }
    }

    fun settle(velocity: Float) {
        if (offset.value <= 0f) return
        if (offset.value > height / 3 || velocity > FLICK) {
            dismiss()
        } else {
            scope.launch { offset.animateTo(0f, tween(200)) }
        }
    }

    /**
     * A list's own scroll never moves the sheet; a drag that goes on down once the list is at its top does, and a drag
     * back up returns the sheet before the list scrolls again. Flings carry nothing over.
     */
    val nested = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (source != NestedScrollSource.UserInput || available.y >= 0f || offset.value <= 0f) return Offset.Zero
            val used = maxOf(available.y, -offset.value)
            dragBy(used)
            return Offset(0f, used)
        }

        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
            dragBy(available.y)
            return Offset(0f, available.y)
        }

        override suspend fun onPreFling(available: Velocity): Velocity {
            if (offset.value <= 0f) return Velocity.Zero
            settle(available.y)
            return available
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
 * The sheet follows the finger from its top: a drag that starts within [zone] of the top (the handle's 24 dp and the
 * header) and that no child took, plus a list's drag past its top ([SheetDrag.nested]). On the sheet's frame, which
 * does not move: the sheet inside it is offset by [SheetDrag.offset].
 */
internal fun Modifier.sheetDrag(drag: SheetDrag, zone: Dp = 24.dp + 64.dp): Modifier =
    onSizeChanged { drag.height = it.height.toFloat().coerceAtLeast(1f) }
        .nestedScroll(drag.nested)
        .pointerInput(drag) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                if (down.position.y - drag.offset.value > zone.toPx()) return@awaitEachGesture
                val tracker = VelocityTracker()
                tracker.addPointerInputChange(down)
                val start = awaitVerticalTouchSlopOrCancellation(down.id) { change, over ->
                    change.consume()
                    drag.dragBy(over)
                } ?: return@awaitEachGesture
                tracker.addPointerInputChange(start)
                verticalDrag(start.id) { change ->
                    tracker.addPointerInputChange(change)
                    drag.dragBy(change.position.y - change.previousPosition.y)
                    change.consume()
                }
                drag.settle(tracker.calculateVelocity().y)
            }
        }
