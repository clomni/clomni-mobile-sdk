package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.FaqRow
import ai.clomni.messenger.presentation.FaqScreen
import ai.clomni.messenger.presentation.HomeScreen
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * The questions (FAQ, contract 1.0.7 §3): the list's bar with "Tez-tez verilən suallar", the search field (searched on
 * this device, in the questions and their answers), then the questions in one card, hairlines between them; a tap
 * opens the answer. Nothing published: "Hələ sual yoxdur"; a search that finds nothing leaves the field alone. A tab's
 * own screen ([tab]) has no back.
 */
@Composable
internal fun FaqListView(
    screen: FaqScreen,
    query: String,
    search: (String) -> Unit,
    theme: ClomniTheme,
    actions: MessengerActions,
    tab: Boolean = false,
) {
    Column(Modifier.fillMaxSize().background(theme.colors.canvas.color)) {
        val scroll = rememberScrollState()
        TopBar(screen.backLabel, actions.back, screen.closeLabel, actions.close, theme, scrolled = scroll.value > 0, showsBack = !tab) {
            TopBarTitle(screen.title, theme)
        }
        Column(
            Modifier.fillMaxWidth().weight(1f).verticalScroll(scroll)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(ClomniTheme.Space.l.dp),
            verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp),
        ) {
            SearchField(query, screen.search, screen.closeLabel, theme, search)
            val empty = screen.empty
            if (empty != null) {
                BasicText(
                    empty,
                    Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.xxl.dp),
                    style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary, FontWeight.SemiBold).copy(textAlign = TextAlign.Center),
                )
            } else if (screen.rows.isNotEmpty()) {
                Column(Modifier.fillMaxWidth().clomniCard(theme)) { FaqRows(screen.rows, theme, actions.openFaqItem) }
            }
        }
    }
}

/**
 * Home's FAQ card: its title, the first three questions with hairlines between them, then "Hamısı" in the brand
 * colour. A question opens its answer; "Hamısı" the list (the FAQ tab with a tab bar).
 */
@Composable
internal fun FaqCardView(card: HomeScreen.FaqCard, theme: ClomniTheme, actions: MessengerActions, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().clomniCard(theme)) {
        BasicText(
            card.title,
            Modifier.padding(bottom = 4.dp),
            style = clomniText(17f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.3f),
        )
        FaqRows(card.questions, theme, actions.openFaqItem)
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        // The row reaches 12 into the card's bottom padding, so the link sits as close to the edge as the rows above.
        Box(
            Modifier.fillMaxWidth().bleed(0.dp, 0.dp, 0.dp, 12.dp).heightIn(min = ClomniTheme.Size.touchTarget.dp)
                .button(card.seeAll, onClick = actions.openFaq),
            Alignment.CenterStart,
        ) {
            BasicText(card.seeAll, style = clomniText(ClomniTheme.FontSize.text, theme.colors.primaryText, FontWeight.Medium))
        }
    }
}

/** Questions one under another, each a 48 dp row of up to two lines, hairlines between them. */
@Composable
private fun FaqRows(rows: List<FaqRow>, theme: ClomniTheme, open: (String) -> Unit) {
    rows.forEachIndexed { index, row ->
        BasicText(
            row.question,
            Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp).button(row.question) { open(row.id) }
                .padding(vertical = ClomniTheme.Space.m.dp),
            style = clomniText(15f, theme.colors.textPrimary, lineHeight = 1.35f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (index < rows.lastIndex) Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
    }
}

/**
 * "Sual axtarın": the composer's field (surface, radius 20, 44 high in a 48 dp target) with the magnifier before it
 * and ✕ to clear it once something is typed.
 */
@Composable
private fun SearchField(query: String, placeholder: String, clearLabel: String, theme: ClomniTheme, search: (String) -> Unit) {
    BasicTextField(
        query,
        search,
        Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp).semantics { contentDescription = placeholder },
        textStyle = clomniText(16f, theme.colors.textPrimary),
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        cursorBrush = SolidColor(theme.colors.primary.color),
        decorationBox = { inner ->
            Row(
                Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(20.dp)).background(theme.colors.surface.color)
                    .padding(start = 12.dp, end = if (query.isEmpty()) 16.dp else 0.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(R.drawable.clomni_ic_search, theme.colors.textSecondary, 20.dp)
                Spacer(Modifier.width(8.dp))
                Box(Modifier.weight(1f).padding(vertical = 10.dp), contentAlignment = Alignment.CenterStart) {
                    if (query.isEmpty()) {
                        BasicText(placeholder, style = clomniText(16f, theme.colors.textSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    inner()
                }
                if (query.isNotEmpty()) {
                    Box(Modifier.size(48.dp).button(clearLabel, CircleShape, 32.dp) { search("") }, Alignment.Center) {
                        Icon(R.drawable.clomni_ic_close, theme.colors.textSecondary, 18.dp)
                    }
                }
            }
        },
    )
}
