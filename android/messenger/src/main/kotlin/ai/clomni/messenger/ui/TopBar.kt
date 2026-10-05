package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/**
 * The bar on the list, a conversation and a news item: back at the start and ✕ at the end, both 40 dp circles in
 * 48 dp slots 12 from the edges; the middle centred on the screen, not between the buttons, so it keeps the same room
 * on both sides and cuts with "…". 64 high (16 + 48: the same row as Home's, DESIGN-PASS-3 A9); the 1 px line
 * under it shows only while the content is scrolled under it ([scrolled]).
 */
@Composable
internal fun TopBar(
    backLabel: String,
    back: () -> Unit,
    closeLabel: String,
    close: () -> Unit,
    theme: ClomniTheme,
    scrolled: Boolean,
    // Null when the screen has its title in its content (a news item).
    middle: (@Composable () -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth().background(theme.colors.background.color).windowInsetsPadding(WindowInsets.statusBars)) {
        // At the user's larger font sizes the middle may need more than 48: the bar grows instead of cutting it.
        Box(Modifier.fillMaxWidth().padding(top = 16.dp).heightIn(min = ClomniTheme.Size.touchTarget.dp)) {
            BackButton(backLabel, theme, back, Modifier.align(Alignment.CenterStart).padding(start = TOP_BAR_EDGE))
            if (middle != null) {
                Box(Modifier.align(Alignment.Center).fillMaxWidth().padding(horizontal = TOP_BAR_MIDDLE), Alignment.Center) { middle() }
            }
            CloseButton(closeLabel, CloseStyle.ON_SURFACE, theme, close, Modifier.align(Alignment.CenterEnd).padding(end = TOP_BAR_EDGE))
        }
        val hairline = with(LocalDensity.current) { 1f.toDp() }
        Box(Modifier.fillMaxWidth().height(hairline).alpha(if (scrolled) 1f else 0f).background(theme.colors.border.color))
    }
}

/** The bar's title: 17 semibold, one line, centred. */
@Composable
internal fun TopBarTitle(title: String, theme: ClomniTheme) = BasicText(
    title,
    Modifier.semantics { heading() },
    style = clomniText(17f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.25f).copy(textAlign = TextAlign.Center),
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
)

/** ‹ in the same circle as ✕: a 20 dp chevron drawn 2 dp thick in the text colour; it points the other way in RTL. */
@Composable
internal fun BackButton(label: String, theme: ClomniTheme, back: () -> Unit, modifier: Modifier = Modifier) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    CircleButton(label, CloseStyle.ON_SURFACE, theme, back, modifier) { ink ->
        val unit = 1.dp.toPx()
        // In a 20 dp square around the centre: from (13, 4) to (7, 10) to (13, 16).
        fun x(dp: Float) = center.x + (if (rtl) -1 else 1) * (dp - 10f) * unit
        fun y(dp: Float) = center.y + (dp - 10f) * unit
        val chevron = Path().apply {
            moveTo(x(13f), y(4f))
            lineTo(x(7f), y(10f))
            lineTo(x(13f), y(16f))
        }
        drawPath(chevron, ink, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** The buttons' slots: 12 from the edges, 48 wide. */
private val TOP_BAR_EDGE = 12.dp

/** The middle keeps clear of both slots, and 8 more: the same on both sides, so it is centred on the screen. */
private val TOP_BAR_MIDDLE = TOP_BAR_EDGE + ClomniTheme.Size.touchTarget.dp + 8.dp
