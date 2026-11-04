package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MessengerTab
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.TabBar
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex

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
 * Which tabs are alive (contract 1.0.7b §3): a tab opened once stays composed while the tab bar is on screen, so going
 * back to it finds it as it was (its scroll, its search, its pictures) at once, with no empty frame. The open tab fades
 * in over the one it replaced, which stays drawn under it until then.
 */
internal class TabStack {
    /** Every tab opened, first opened first. */
    val opened = mutableStateListOf<MessengerTab>()

    var selected by mutableStateOf<MessengerTab?>(null)
        private set

    /** The tab [selected] replaced, drawn under it while it fades in; null once it has. */
    var under by mutableStateOf<MessengerTab?>(null)
        private set

    /** [tab] is the one shown; the same again changes nothing. */
    fun show(tab: MessengerTab) {
        if (tab == selected) return
        under = selected
        selected = tab
        if (tab !in opened) opened += tab
    }

    /** The fade is over: only [selected] is drawn. */
    fun settled() {
        under = null
    }
}

/**
 * The tabs of [bar] over the bar, [page] drawing each: every tab [stack] opened stays composed, only the open one (and,
 * for its fade, the one before, under it) is placed: the others are not drawn, touched or read out. A change of tab is
 * a 200 ms fade (ease-out) of the new tab over the old, nothing slides; with the system's animations off it is at once.
 */
@Composable
internal fun TabPages(bar: TabBar, stack: TabStack, theme: ClomniTheme, select: (MessengerTab) -> Unit, page: @Composable (MessengerTab) -> Unit) {
    val selected = stack.selected ?: MessengerTab.HOME
    val still = reduceMotion()
    WithTabBar(bar, selected, theme, select) {
        for (tab in stack.opened) {
            if (tab !in bar) continue
            key(tab) {
                val open = tab == selected
                val drawn = open || tab == stack.under
                // A tab a change opens starts unseen; the first one, and the open one when the tabs come back, are there.
                val fade = remember { Animatable(if (open && stack.under == null) 1f else 0f) }
                LaunchedEffect(open) {
                    if (!open) return@LaunchedEffect fade.snapTo(0f)
                    if (still) fade.snapTo(1f) else fade.animateTo(1f, tween(TAB_FADE_MS, easing = LinearOutSlowInEasing))
                    stack.settled()
                }
                Box(
                    Modifier.zIndex(if (open) 1f else 0f).graphicsLayer { alpha = if (open) fade.value else 1f }.layout { measurable, constraints ->
                        val placeable = measurable.measure(constraints)
                        layout(placeable.width, placeable.height) { if (drawn) placeable.place(0, 0) }
                    },
                ) { page(tab) }
            }
        }
    }
}

/** Contract 1.0.7b §3: 180–220 ms. */
internal const val TAB_FADE_MS = 200

/**
 * Brief 7.3: the tabs side by side over a hairline, each an icon 22 over its label 11; the open tab's icon is filled in
 * the brand colour and its label text_primary 600, the others text_secondary. The conversations carry the unread count
 * on their icon (contract 1.0.7b §2). At least 56 high, taller with a large font.
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
            // 2 more over the icon than under the label: the badge, half over the icon's top, stays inside the tab.
            .padding(top = 10.dp, bottom = 6.dp, start = 4.dp, end = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Box(Modifier.size(TAB_ICON)) {
            Icon(tab.kind.icon(isSelected), if (isSelected) theme.colors.primaryText else theme.colors.textSecondary, TAB_ICON)
            // Contract 1.0.7b §2: 16 high, a circle for one figure and wider for more (4 each side), white 10 semibold
            // on the unread red, ringed 1.5 in the bar's colour so it stands apart from the icon. Its start 4 past the
            // icon's centre, its middle on the icon's top edge (mirrored right to left); it takes no room, so the icon
            // stays in the middle of its tab whatever the number. A fixed size: TalkBack reads the number with the tab.
            tab.badge?.let { count ->
                BasicText(
                    count,
                    Modifier.offset(TAB_ICON / 2 + 4.dp - BADGE_RING, -(8.dp + BADGE_RING))
                        .wrapContentSize(Alignment.TopStart, unbounded = true)
                        .border(BADGE_RING, theme.colors.background.color, CircleShape)
                        .padding(BADGE_RING)
                        .background(theme.colors.unread.color, CircleShape)
                        .sizeIn(minWidth = 16.dp, minHeight = 16.dp)
                        .padding(horizontal = 4.dp),
                    style = clomniText(with(LocalDensity.current) { 10.dp.toSp().value }, RgbColor.WHITE, FontWeight.SemiBold, lineHeight = 1.6f)
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

private val TAB_ICON = 22.dp
private val BADGE_RING = 1.5.dp

/** Material's icons, outlined, and filled for the open tab. */
private fun MessengerTab.icon(filled: Boolean): Int = when (this) {
    MessengerTab.HOME -> if (filled) R.drawable.clomni_ic_home_filled else R.drawable.clomni_ic_home
    MessengerTab.MESSAGES -> if (filled) R.drawable.clomni_ic_chat_filled else R.drawable.clomni_ic_chat
    MessengerTab.NEWS -> if (filled) R.drawable.clomni_ic_news_filled else R.drawable.clomni_ic_news
    MessengerTab.FAQ -> if (filled) R.drawable.clomni_ic_help_filled else R.drawable.clomni_ic_help
}
