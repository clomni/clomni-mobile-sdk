package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.NewsScreen
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * A news item on Home (DESIGN-PASS-2, news): its picture on top at 16:9 (radius 12) when it has one, the title 16
 * semibold and the short text 14 grey, two lines each. A tap opens the item.
 */
@Composable
internal fun NewsCardView(card: HomeScreen.NewsCard, theme: ClomniTheme, open: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().clomniCard(theme, card.accessibilityLabel) { open(card.id) }) {
        card.imageUrl?.let { url ->
            RemoteImage(
                url,
                ImageSizing.Kind.HEADER,
                LocalConfiguration.current.screenWidthDp.toFloat(),
                theme.colors.surface.color,
                Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(12.dp)),
            )
            Spacer(Modifier.height(12.dp))
        }
        BasicText(
            card.title,
            style = clomniText(16f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.3f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        card.summary?.let {
            BasicText(
                it,
                Modifier.padding(top = 4.dp),
                style = clomniText(14f, theme.colors.textSecondary, lineHeight = 1.4f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * A news item's own screen: back and ✕ on top, then its picture, the title 24 bold, the date 13, the text (bold,
 * italic, links, lists) and its button. The button's link goes through the app's `Clomni.onLink`; without one the
 * system opens it.
 */
@Composable
internal fun NewsView(screen: NewsScreen, theme: ClomniTheme, back: () -> Unit, close: () -> Unit, openLink: (String) -> Unit) {
    Column(Modifier.fillMaxSize().background(theme.colors.background.color)) {
        val scroll = rememberScrollState()
        TopBar(screen.backLabel, back, screen.closeLabel, close, theme, scrolled = scroll.value > 0)
        Column(
            Modifier.fillMaxWidth().weight(1f).verticalScroll(scroll)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(start = 20.dp, end = 20.dp, bottom = 32.dp),
        ) {
            screen.imageUrl?.let { url ->
                RemoteImage(
                    url,
                    ImageSizing.Kind.HEADER,
                    LocalConfiguration.current.screenWidthDp.toFloat(),
                    theme.colors.surface.color,
                    Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(12.dp)),
                )
                Spacer(Modifier.height(20.dp))
            }
            BasicText(
                screen.title,
                Modifier.semantics { heading() },
                style = clomniText(24f, theme.colors.textPrimary, FontWeight.Bold, lineHeight = 1.25f, letterSpacing = -0.2f),
            )
            screen.date?.let {
                BasicText(it, Modifier.padding(top = 8.dp), style = clomniText(13f, theme.colors.textSecondary))
            }
            Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (block in screen.blocks) {
                    Row {
                        if (block.bullet) {
                            BasicText("•", style = clomniText(16f, theme.colors.textPrimary, lineHeight = 1.5f))
                            Spacer(Modifier.width(8.dp))
                        }
                        BasicText(
                            attributedText(block.runs, theme.colors.primaryText),
                            style = clomniText(16f, theme.colors.textPrimary, lineHeight = 1.5f),
                        )
                    }
                }
            }
            screen.button?.let { button ->
                Spacer(Modifier.height(24.dp))
                Box(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp))
                        .background(theme.colors.primary.color).button(button.text, RoundedCornerShape(24.dp)) { openLink(button.url) }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    Alignment.Center,
                ) {
                    BasicText(
                        button.text,
                        style = clomniText(16f, theme.colors.onPrimary, FontWeight.SemiBold).copy(textAlign = TextAlign.Center),
                    )
                }
            }
        }
    }
}
