package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeController
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import ai.clomni.messenger.protocol.MessengerConfig
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** What the screens hand back to whoever presents the messenger (CM-074 wires these to navigation). */
internal class MessengerActions(
    val close: () -> Unit = {},
    /** The list's back arrow: Home. */
    val back: () -> Unit = {},
    /** Home's "Mesajlar" card. */
    val openMessages: () -> Unit = {},
    /** A news card: the item's screen. */
    val openNews: (String) -> Unit = {},
    val newConversation: () -> Unit = {},
    val openConversation: (String) -> Unit = {},
    val retry: () -> Unit = {},
)

/**
 * Home and the conversations list, kept current by [controller], which lives as long as the messenger is open: going
 * to a conversation and back finds Home as it was, never its default texts first.
 */
internal class MessengerScreens(val controller: HomeController) {
    var home by mutableStateOf(controller.home)
        private set
    var messages by mutableStateOf(controller.messages)
        private set
    var config by mutableStateOf(controller.config)
        private set

    fun refresh() {
        home = controller.home
        messages = controller.messages
        config = controller.config
    }
}

/** [MessengerScreens] following [controller] while composed: loaded once, stopped when the messenger closes. */
@Composable
internal fun rememberMessengerScreens(controller: HomeController, live: Boolean): MessengerScreens {
    val screens = remember(controller) { MessengerScreens(controller) }
    DisposableEffect(controller, live) {
        if (live) {
            controller.onChange = screens::refresh
            controller.load()
        }
        onDispose {
            controller.onChange = null
            if (live) controller.stop()
        }
    }
    return screens
}

/**
 * The screens' actions for Home and the list: a new conversation (a draft with [openedFrom], created by its first
 * message), one picked from the list, the list itself.
 */
@Composable
internal fun rememberMessengerActions(
    controller: HomeController,
    openedFrom: String?,
    close: () -> Unit,
    back: () -> Unit,
    openMessages: () -> Unit,
    openConversation: (String) -> Unit,
    openNews: (String) -> Unit,
): MessengerActions = remember(controller, openedFrom, close, back, openMessages, openConversation, openNews) {
    MessengerActions(
        close = close,
        back = back,
        openMessages = openMessages,
        openNews = { id ->
            controller.newsOpened(id)
            openNews(id)
        },
        newConversation = { openConversation(controller.newConversation(openedFrom)) },
        openConversation = openConversation,
        retry = controller::retry,
    )
}
