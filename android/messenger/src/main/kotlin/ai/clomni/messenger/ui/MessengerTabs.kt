package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MessengerTab
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.TabBar
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * A tab's screen with the tab bar under it (contract 1.0.7 §3). The bar keeps the navigation bar's room, so the screen
 * above it does not keep it again. Without a [bar] (the panel's tab_bar off) the screen is as it was.
 */
@Composable
internal fun WithTabBar(bar: TabBar?, selected: MessengerTab, theme: ClomniTheme, select: (MessengerTab) -> Unit, content: @Composable () -> Unit) {
    if (bar == null) return content()
    Column(Modifier.fillMaxSize().background(theme.colors.background.color)) {
        Box(Modifier.weight(1f).fillMaxWidth().consumeWindowInsets(WindowInsets.navigationBars)) { content() }
        MessengerTabBar(bar, selected, theme, select)
    }
}

/**
 * Brief 7.3: the tabs side by side over a hairline, each an icon 22 over its label 11; the open tab's icon is filled in
 * the brand colour and its label text_primary 600, the others text_secondary. The conversations carry the unread count
 * on their icon (the unread red, white figures, "99+" at most). At least 56 high, taller with a large font.
 */
@Composable
internal fun MessengerTabBar(bar: TabBar, selected: MessengerTab, theme: ClomniTheme, select: (MessengerTab) -> Unit) {
    Column(Modifier.fillMaxWidth().background(theme.colors.background.color).windowInsetsPadding(WindowInsets.navigationBars)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).height(IntrinsicSize.Min)) {
            for (tab in bar.tabs) TabItem(tab, tab.kind == selected, theme) { select(tab.kind) }
        }
    }
}

@Composable
private fun RowScope.TabItem(tab: TabBar.Tab, isSelected: Boolean, theme: ClomniTheme, select: () -> Unit) {
    val ink = if (isSelected) theme.colors.textPrimary else theme.colors.textSecondary
    Column(
        Modifier.weight(1f).fillMaxHeight()
            // A press shows as a circle round the tab's middle, not a grey block over the cell.
            .clickable(interactionSource = null, indication = ShapedIndication(CircleShape, 56.dp, scale = 1f), role = Role.Tab, onClick = select)
            .clearAndSetSemantics {
                contentDescription = tab.accessibilityLabel
                role = Role.Tab
                selected = isSelected
            }
            .padding(top = 8.dp, bottom = 8.dp, start = 4.dp, end = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Box {
            Icon(tab.kind.icon(isSelected), if (isSelected) theme.colors.primaryText else theme.colors.textSecondary, 22.dp)
            tab.badge?.let { count ->
                BasicText(
                    count,
                    Modifier.align(Alignment.TopEnd).offset(x = 9.dp, y = (-5).dp)
                        .border(1.5.dp, theme.colors.background.color, RoundedCornerShape(9.dp))
                        .padding(1.5.dp)
                        .background(theme.colors.unread.color, RoundedCornerShape(8.dp))
                        .sizeIn(minWidth = 16.dp, minHeight = 16.dp)
                        .padding(horizontal = 4.dp),
                    style = clomniText(10f, RgbColor.WHITE, FontWeight.SemiBold, lineHeight = 1.6f)
                        .copy(textAlign = TextAlign.Center),
                    maxLines = 1,
                )
            }
        }
        BasicText(
            tab.title,
            style = clomniText(ClomniTheme.FontSize.meta, ink, if (isSelected) FontWeight.SemiBold else FontWeight.Medium, lineHeight = 1.3f)
                .copy(textAlign = TextAlign.Center),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Material's icons, outlined, and filled for the open tab. */
private fun MessengerTab.icon(filled: Boolean): Int = when (this) {
    MessengerTab.HOME -> if (filled) R.drawable.clomni_ic_home_filled else R.drawable.clomni_ic_home
    MessengerTab.MESSAGES -> if (filled) R.drawable.clomni_ic_chat_filled else R.drawable.clomni_ic_chat
    MessengerTab.NEWS -> if (filled) R.drawable.clomni_ic_news_filled else R.drawable.clomni_ic_news
    MessengerTab.FAQ -> if (filled) R.drawable.clomni_ic_help_filled else R.drawable.clomni_ic_help
}
