package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.QuickReplyBlock
import ai.clomni.messenger.presentation.ReplyButton
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * The live step's choices (operator, 2026-10-04): capsules aligned to the end, each on its own line whatever the
 * step's layout, 8 apart, 12 under the last message; then a grey "← Geri". A tap fades them out (200 ms) and the
 * choice stays as the user's message.
 */
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
    val buttons = block.buttons + listOfNotNull(block.back)
    Box(Modifier.fillMaxWidth().padding(top = 12.dp).alpha(opacity), Alignment.CenterEnd) {
        // A long choice wraps inside 85% of the width rather than running to the other edge.
        Column(Modifier.fillMaxWidth(0.85f), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.End) {
            for (button in buttons) Pill(button, button === block.back, theme, enabled = !chosen, choose)
        }
    }
}

/**
 * A capsule: at least 44 high, white (surface in dark) with a 1.5 dp border in the text colour at 18% (24% in dark),
 * 20 to its sides and 10 above and below, text 16 regular that wraps and is never cut; pressed, the text colour at
 * 6%. Its tap target reaches 48 dp.
 */
@Composable
private fun Pill(button: ReplyButton, isBack: Boolean, theme: ClomniTheme, enabled: Boolean, choose: (String) -> Unit) {
    val shape = RoundedCornerShape(50)
    val reach = 2.dp
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val text = theme.colors.textPrimary.color
    val fill = when {
        pressed -> text.copy(alpha = 0.06f)
        theme.isDark -> theme.colors.surface.color
        else -> theme.colors.background.color
    }
    val target = Modifier.bleed(vertical = reach).let {
        if (enabled) {
            it.clickable(interaction, indication = null, role = Role.Button) { choose(button.id) }
                .clearAndSetSemantics { contentDescription = button.accessibilityLabel }
        } else {
            it
        }
    }
    Box(target.padding(vertical = reach).wrapContentWidth(Alignment.End)) {
        Box(
            Modifier.heightIn(min = 44.dp)
                .clip(shape)
                .background(fill)
                .border(1.5.dp, text.copy(alpha = if (theme.isDark) 0.24f else 0.18f), shape)
                .padding(horizontal = 20.dp, vertical = 10.dp),
            Alignment.Center,
        ) {
            BasicText(
                button.title,
                style = clomniText(16f, if (isBack) theme.colors.textSecondary else theme.colors.textPrimary, lineHeight = 1.3f)
                    .copy(textAlign = TextAlign.Start),
            )
        }
    }
}
