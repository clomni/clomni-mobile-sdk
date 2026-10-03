package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.ConversationRow
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.MessagesScreen
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * The Messages tab: the conversations, newest first, under the same "Bizə mesaj göndərin" card as Home; an empty list
 * says "Hələ söhbət yoxdur".
 */
@Composable
internal fun MessagesView(screen: MessagesScreen, theme: ClomniTheme, closeLabel: String, actions: MessengerActions) {
    Column(Modifier.fillMaxSize().background(theme.colors.canvas.color)) {
        TitleBar(screen.title, screen.backLabel, closeLabel, theme, actions.back, actions.close)
        screen.offline?.let { OfflineStrip(it, theme) }
        val padding = Modifier.padding(ClomniTheme.Space.l.dp)
        val spacing = Arrangement.spacedBy(ClomniTheme.Space.m.dp)
        when (screen.phase) {
            // The first time: the indicator in the middle (after 300 ms); afterwards the cached list at once.
            HomeScreen.Phase.LOADING -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                LoadingSpinner(true, theme.colors.primary, screen.loadingLabel)
            }
            HomeScreen.Phase.FAILED -> screen.failure?.let { Box(padding) { FailureView(it, theme, actions.retry) } }
            HomeScreen.Phase.READY -> Column(Modifier.verticalScroll(rememberScrollState()).then(padding), spacing) {
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

/** The bar with the bottom hairline: back at the start, the title 17 semibold in the middle, ✕ at the end. */
@Composable
private fun TitleBar(title: String, backLabel: String, closeLabel: String, theme: ClomniTheme, back: () -> Unit, close: () -> Unit) {
    Column(Modifier.background(theme.colors.background.color).windowInsetsPadding(WindowInsets.statusBars)) {
        Box(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp).heightIn(min = ClomniTheme.Size.touchTarget.dp)) {
            Box(
                Modifier.align(Alignment.CenterStart).padding(start = 4.dp).size(ClomniTheme.Size.touchTarget.dp).button(backLabel, back),
                Alignment.Center,
            ) {
                Icon(R.drawable.clomni_ic_back, theme.colors.textPrimary, 10.dp, Modifier.size(10.dp, 17.dp))
            }
            BasicText(
                title,
                Modifier.align(Alignment.Center).semantics { heading() },
                style = clomniText(17f, theme.colors.textPrimary, FontWeight.SemiBold),
            )
            CloseButton(closeLabel, CloseStyle.ON_SURFACE, theme, close, Modifier.align(Alignment.CenterEnd).padding(end = 12.dp))
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
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
