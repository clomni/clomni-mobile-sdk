package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.QuickReplyBlock
import ai.clomni.messenger.presentation.ReplyButton
import ai.clomni.messenger.protocol.MessageContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * The live step's buttons: end-aligned pills, one under another (vertical) or side by side and wrapping (chips), then
 * a grey "← Geri". A tap fades them out (200 ms) and the choice stays as the user's message.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun QuickRepliesView(block: QuickReplyBlock, theme: ClomniTheme, tap: (String) -> Unit) {
    var chosen by remember(block.messageId) { mutableStateOf(false) }
    val opacity by animateFloatAsState(if (chosen) 0f else 1f, tween(200), label = "replies")
    val choose = { id: String ->
        if (!chosen) {
            chosen = true
            tap(id)
        }
    }
    // Pills a row apart are 16 dp apart: their 48 dp targets meet without covering each other (brief 7.6).
    val gap = Arrangement.spacedBy(ClomniTheme.Space.xs.dp, Alignment.End)
    val rows = Arrangement.spacedBy(16.dp)
    val buttons = block.buttons + listOfNotNull(block.back)
    val modifier = Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.s.dp).alpha(opacity)
    Box(modifier, Alignment.CenterEnd) {
        val inner = Modifier.widthIn(max = 240.dp)
        if (block.layout == MessageContent.QuickRepliesLayout.CHIPS) {
            FlowRow(inner, horizontalArrangement = gap, verticalArrangement = rows) {
                for (button in buttons) Pill(button, button === block.back, theme, enabled = !chosen, choose)
            }
        } else {
            Column(inner, verticalArrangement = rows, horizontalAlignment = Alignment.End) {
                for (button in buttons) Pill(button, button === block.back, theme, enabled = !chosen, choose)
            }
        }
    }
}

/**
 * Background, a 1 dp primaryLine border, primary text 14/500, radius 18, padding 7×13; up to two lines, then "…". The
 * tap target reaches 48 dp where the pill is smaller.
 */
@Composable
private fun Pill(button: ReplyButton, isBack: Boolean, theme: ClomniTheme, enabled: Boolean, choose: (String) -> Unit) {
    val shape = RoundedCornerShape(ClomniTheme.Radius.pill.dp)
    val reach = 8.dp
    val target = Modifier.bleed(vertical = reach).let {
        if (enabled) it.button(button.accessibilityLabel) { choose(button.id) } else it
    }
    Box(target.padding(vertical = reach).wrapContentWidth(Alignment.End)) {
        BasicText(
            button.title,
            Modifier.clip(shape)
                .background(theme.colors.background.color)
                .border(1.dp, if (isBack) theme.colors.border.color else theme.colors.primaryLine.color, shape)
                .padding(vertical = 8.dp, horizontal = 12.dp),
            style = clomniText(
                ClomniTheme.FontSize.text,
                if (isBack) theme.colors.textSecondary else theme.colors.primaryText,
                if (isBack) FontWeight.Normal else FontWeight.Medium,
                lineHeight = 1.3f,
            ).copy(textAlign = TextAlign.End),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
