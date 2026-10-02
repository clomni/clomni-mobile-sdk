package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeController
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import ai.clomni.messenger.protocol.MessengerConfig
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** What the screens hand back to whoever presents the messenger (CM-074 wires these to navigation). */
internal class MessengerActions(
    val close: () -> Unit = {},
    val newConversation: () -> Unit = {},
    val openConversation: (String) -> Unit = {},
    val retry: () -> Unit = {},
)

internal enum class MessengerTab { HOME, MESSAGES }

/**
 * The messenger's first screen, kept current by [controller]: Home and Messages with the tab bar under them. Opening a
 * conversation (a new one is a draft with [openedFrom], created by its first message) and closing the messenger come
 * out as callbacks; MessengerRoot puts them on the messenger's route.
 */
@Composable
internal fun ClomniMessenger(
    controller: HomeController,
    openedFrom: String?,
    close: () -> Unit,
    openConversation: (String) -> Unit,
) {
    var screens by remember { mutableStateOf(Screens(controller.home, controller.messages, controller.config)) }
    DisposableEffect(controller) {
        controller.onChange = { screens = Screens(controller.home, controller.messages, controller.config) }
        controller.load()
        onDispose {
            controller.onChange = null
            controller.stop()
        }
    }
    val theme = rememberTheme(screens.config)
    val actions = remember(controller, openedFrom, close, openConversation) {
        MessengerActions(
            close = close,
            newConversation = { openConversation(controller.newConversation(openedFrom)) },
            openConversation = openConversation,
            retry = controller::retry,
        )
    }
    MessengerTabs(screens.home, screens.messages, theme, actions)
}

private class Screens(val home: HomeScreen, val messages: MessagesScreen, val config: MessengerConfig?)

/** Home and Messages with the tab bar under them. */
@Composable
internal fun MessengerTabs(
    home: HomeScreen,
    messages: MessagesScreen,
    theme: ClomniTheme,
    actions: MessengerActions,
    initialTab: MessengerTab = MessengerTab.HOME,
) {
    var tab by rememberSaveable { mutableStateOf(initialTab) }
    Column(Modifier.fillMaxSize().background(theme.colors.background.color)) {
        Crossfade(tab, Modifier.weight(1f), animationSpec = tween(200), label = "tab") { selected ->
            when (selected) {
                MessengerTab.HOME -> HomeView(home, theme, actions)
                MessengerTab.MESSAGES -> MessagesView(messages, theme, home.header.closeLabel, actions)
            }
        }
        TabBar(home.tabs, tab, { tab = it }, theme)
    }
}

/**
 * Ana səhifə, Mesajlar: icon 22, label 11; the active tab in the text colour and semibold; a red dot 8 on Mesajlar
 * while something is unread.
 */
@Composable
private fun TabBar(tabs: HomeScreen.Tabs, selected: MessengerTab, select: (MessengerTab) -> Unit, theme: ClomniTheme) {
    Column(Modifier.background(theme.colors.background.color).windowInsetsPadding(WindowInsets.navigationBars)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        Row(Modifier.fillMaxWidth().padding(top = 9.dp)) {
            val home = selected == MessengerTab.HOME
            val homeIcon = if (home) R.drawable.clomni_ic_home_filled else R.drawable.clomni_ic_home
            TabItem(tabs.home, tabs.home, homeIcon, home, false, theme) { select(MessengerTab.HOME) }
            TabItem(
                tabs.messages,
                tabs.messagesAccessibilityLabel,
                if (!home) R.drawable.clomni_ic_chat_filled else R.drawable.clomni_ic_chat,
                !home,
                tabs.messagesUnread,
                theme,
            ) { select(MessengerTab.MESSAGES) }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TabItem(
    title: String,
    label: String,
    icon: Int,
    isSelected: Boolean,
    showsDot: Boolean,
    theme: ClomniTheme,
    select: () -> Unit,
) {
    val color = if (isSelected) theme.colors.textPrimary else theme.colors.textSecondary
    Column(
        Modifier.weight(1f).heightIn(min = ClomniTheme.Size.touchTarget.dp)
            .clickable(role = Role.Tab, onClick = select)
            .clearAndSetSemantics {
                contentDescription = label
                selected = isSelected
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xxs.dp),
    ) {
        Box {
            Icon(icon, color, ClomniTheme.Size.tabIcon.dp)
            if (showsDot) {
                Box(
                    Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-1).dp)
                        .size(ClomniTheme.Size.tabDot.dp + 4.dp).clip(CircleShape)
                        .border(2.dp, theme.colors.background.color, CircleShape)
                        .padding(2.dp).clip(CircleShape).background(theme.colors.unread.color),
                )
            }
        }
        BasicText(
            title,
            style = clomniText(
                ClomniTheme.FontSize.meta,
                color,
                if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                lineHeight = 1.3f,
            ),
            maxLines = 1,
        )
    }
}
