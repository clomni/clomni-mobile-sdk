package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.ConversationRow
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * The Messages tab: the conversations, newest first, under the same "Bizə mesaj göndərin" card as Home; an empty list
 * says "Hələ söhbət yoxdur".
 */
@Composable
internal fun MessagesView(screen: MessagesScreen, theme: ClomniTheme, closeLabel: String, actions: MessengerActions) {
    WithOfflineCapsule(screen.offline, screen.connected, theme) { bar -> MessagesBody(screen, theme, closeLabel, actions, bar) }
}

@Composable
private fun MessagesBody(screen: MessagesScreen, theme: ClomniTheme, closeLabel: String, actions: MessengerActions, bar: Modifier) {
    Column(Modifier.fillMaxSize().background(theme.colors.canvas.color)) {
        val scroll = rememberScrollState()
        Box(bar) {
            TopBar(screen.backLabel, actions.back, closeLabel, actions.close, theme, scrolled = scroll.value > 0) {
                TopBarTitle(screen.title, theme)
            }
        }
        val padding = Modifier.padding(ClomniTheme.Space.l.dp)
        val spacing = Arrangement.spacedBy(ClomniTheme.Space.m.dp)
        when (screen.phase) {
            // The first time: the indicator in the middle (after 300 ms); afterwards the cached list at once.
            HomeScreen.Phase.LOADING -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                LoadingSpinner(true, theme.colors.primary, screen.loadingLabel)
            }
            HomeScreen.Phase.FAILED -> screen.failure?.let { Box(padding) { FailureView(it, theme, actions.retry) } }
            HomeScreen.Phase.READY -> Column(Modifier.verticalScroll(scroll).then(padding), spacing) {
                NewConversationCardView(screen.newConversation, theme, actions.newConversation)
                val empty = screen.empty
                if (empty != null) {
                    // textPrimary: the secondary grey on the canvas is 4.32:1, under WCAG AA.
                    BasicText(
                        empty,
                        Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.xxl.dp),
                        style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary, FontWeight.SemiBold)
                            .copy(textAlign = TextAlign.Center),
                    )
                } else {
                    ConversationList(screen.rows, theme, actions.openConversation)
                }
            }
        }
    }
}

/** The conversations in one card, separated by hairlines. */
@Composable
private fun ConversationList(rows: List<ConversationRow>, theme: ClomniTheme, open: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().clomniCard(theme)) {
        rows.forEachIndexed { index, row ->
            Box(
                Modifier.fillMaxWidth()
                    .heightIn(min = ClomniTheme.Size.touchTarget.dp)
                    .button(row.accessibilityLabel) { open(row.id) }
                    .padding(vertical = ClomniTheme.Space.m.dp),
                Alignment.CenterStart,
            ) {
                ConversationRowView(row, theme)
            }
            if (index < rows.lastIndex) Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        }
    }
}
