package ai.clomni.messenger.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.node.CompositionLocalConsumerModifierNode
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.currentValueOf
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import kotlinx.coroutines.launch

/** The press highlight's colour: the text colour, faint; [MessengerRoot] sets it for the theme. */
internal val LocalPressTint = staticCompositionLocalOf { Color.Black.copy(alpha = 0.08f) }

/**
 * The highlight while pressed, cut to the element's own [shape] (a pill, a circle, a card's corners), never the square
 * of its touch target. [diameter] draws it that size around the centre: a 40 dp circle in a 48 dp target. Pressed,
 * the element also shrinks to [scale] on a spring and springs back when let go (M6); not with the system's
 * animations off.
 */
internal data class ShapedIndication(val shape: Shape, val diameter: Dp? = null, val scale: Float = 0.97f) : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = Node(interactionSource, shape, diameter, scale)

    private class Node(
        private val source: InteractionSource,
        private val shape: Shape,
        private val diameter: Dp?,
        private val pressedScale: Float,
    ) : Modifier.Node(), DrawModifierNode, CompositionLocalConsumerModifierNode {
        private var presses = 0
        private val shrink = Animatable(1f)

        override fun onAttach() {
            val still = Motion.reduced(currentValueOf(LocalContext))
            coroutineScope.launch {
                source.interactions.collect {
                    when (it) {
                        is PressInteraction.Press -> presses++
                        is PressInteraction.Release, is PressInteraction.Cancel -> presses = (presses - 1).coerceAtLeast(0)
                    }
                    invalidateDraw()
                    if (!still) {
                        launch { shrink.animateTo(if (presses > 0) pressedScale else 1f, Motion.press()) { invalidateDraw() } }
                    }
                }
            }
        }

        override fun ContentDrawScope.draw() {
            scale(shrink.value) {
                this@draw.drawContent()
                if (presses == 0) return@scale
                val area = diameter?.toPx()?.let { Size(it, it) } ?: size
                translate((size.width - area.width) / 2, (size.height - area.height) / 2) {
                    drawOutline(shape.createOutline(area, layoutDirection, this), currentValueOf(LocalPressTint))
                }
            }
        }
    }
}
