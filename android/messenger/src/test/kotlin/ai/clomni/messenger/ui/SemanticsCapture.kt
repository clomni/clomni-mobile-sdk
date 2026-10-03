package ai.clomni.messenger.ui

import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.platform.AbstractComposeView
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.cash.paparazzi.RenderExtension
import org.junit.Assert.assertTrue

/**
 * A Paparazzi extension that draws nothing: after layout it keeps what TalkBack would find on the screen, the merged
 * semantics tree of every Compose view in reading order, so a snapshot test can check it too.
 */
class SemanticsCapture : RenderExtension {
    /** One stop of TalkBack: what it says, and what it is. Sizes in dp. */
    data class Element(
        val label: String,
        val role: Role?,
        val clickable: Boolean,
        val heading: Boolean,
        val liveRegion: LiveRegionMode?,
        val width: Float,
        val height: Float,
        /** From the screen's end edge and top, dp. */
        val fromEnd: Float = 0f,
        val top: Float = 0f,
        /** A link inside running text: as tall as its line, which WCAG 2.5.8 exempts ("inline"). */
        val inline: Boolean = false,
    ) {
        override fun toString() = buildString {
            append(label)
            role?.let { append(" [$it]") }
            if (clickable && role == null) append(" [click]")
            if (heading) append(" [heading]")
            liveRegion?.let { append(" [live]") }
        }
    }

    var elements: List<Element> = emptyList()
        private set

    override fun renderView(contentView: View): View {
        elements = emptyList()
        contentView.viewTreeObserver.addOnGlobalLayoutListener { elements = capture(contentView) }
        return contentView
    }

    private fun capture(view: View): List<Element> {
        val density = view.resources.displayMetrics.density
        val found = mutableListOf<Element>()
        fun visit(node: SemanticsNode) {
            val config = node.config
            if (config.getOrNull(SemanticsProperties.InvisibleToUser) != null) return
            val description = config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString(" ")
            val text = (config.getOrNull(SemanticsProperties.Text).orEmpty() + listOfNotNull(config.getOrNull(SemanticsProperties.EditableText)))
                .joinToString(" ") { it.text }
            val clickable = config.getOrNull(SemanticsActions.OnClick) != null && config.getOrNull(SemanticsProperties.Disabled) == null
            val label = description.ifEmpty { text }
            if (label.isNotEmpty() || clickable) {
                found += Element(
                    label = label,
                    role = config.getOrNull(SemanticsProperties.Role),
                    clickable = clickable,
                    heading = config.getOrNull(SemanticsProperties.Heading) != null,
                    liveRegion = config.getOrNull(SemanticsProperties.LiveRegion),
                    width = node.size.width / density,
                    height = node.size.height / density,
                    fromEnd = (view.width - node.boundsInRoot.right) / density,
                    top = node.boundsInRoot.top / density,
                    // Compose marks a text link's node with this key; it is not public API, so it is matched by name.
                    inline = config.any { it.key.name == "LinkTestMarker" },
                )
            }
            node.children.forEach(::visit)
        }
        fun walk(v: View) {
            if (v is AbstractComposeView) {
                (v.getChildAt(0) as? ViewRootForTest)?.let { visit(it.semanticsOwner.rootSemanticsNode) }
            } else if (v is ViewGroup) {
                for (i in 0 until v.childCount) walk(v.getChildAt(i))
            }
        }
        walk(view)
        return found
    }

    /** Brief 7.6: everything that can be tapped is at least 48 × 48 dp, however small it looks; links in text excepted. */
    fun assertTouchTargets(screen: String) {
        val small = elements.filter { it.clickable && !it.inline && (it.width < 47.5f || it.height < 47.5f) }
        assertTrue("$screen: smaller than 48 dp: ${small.joinToString { "\"$it\" ${it.width}×${it.height}" }}", small.isEmpty())
    }
}
