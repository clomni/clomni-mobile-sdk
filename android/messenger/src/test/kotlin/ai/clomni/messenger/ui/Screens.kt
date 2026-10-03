package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import androidx.compose.runtime.Composable

/** Home or the list, for the screenshot tests. */
internal enum class Shown { HOME, MESSAGES }

@Composable
internal fun MessengerScreenAt(
    home: HomeScreen,
    messages: MessagesScreen,
    theme: ClomniTheme,
    actions: MessengerActions,
    shown: Shown = Shown.HOME,
) = when (shown) {
    Shown.HOME -> HomeView(home, theme, actions)
    Shown.MESSAGES -> MessagesView(messages, theme, home.header.closeLabel, actions)
}
