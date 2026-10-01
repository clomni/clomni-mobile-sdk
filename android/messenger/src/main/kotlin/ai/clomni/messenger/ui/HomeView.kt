package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/** The Home tab (brief 8·7.3): the brand header with the greeting, and the cards riding up over it by 40. */
@Composable
internal fun HomeView(screen: HomeScreen, theme: ClomniTheme, actions: MessengerActions) {
    Column(Modifier.fillMaxSize().background(theme.colors.canvas.color).verticalScroll(rememberScrollState())) {
        HomeHeader(screen.header, theme, actions.close)
        screen.offline?.let { OfflineStrip(it, theme) }
        val cards = Modifier.padding(horizontal = ClomniTheme.Space.l.dp)
        // Under the offline strip the cards cannot ride up over the header.
        val placed = if (screen.offline == null) {
            cards.rise(ClomniTheme.Size.cardOverlap.dp)
        } else {
            cards.padding(top = ClomniTheme.Space.m.dp)
        }
        HomeCards(screen, theme, actions, placed.padding(bottom = ClomniTheme.Space.xxl.dp))
    }
}

@Composable
private fun HomeHeader(header: HomeScreen.Header, theme: ClomniTheme, close: () -> Unit) {
    val text = theme.colors.onPrimary
    Column(
        Modifier.fillMaxWidth()
            // The only gradient in the messenger: primaryDark at the top to primary, behind the status bar too.
            .background(Brush.verticalGradient(listOf(theme.colors.primaryDark.color, theme.colors.primary.color)))
            .windowInsetsPadding(WindowInsets.statusBars)
            // 62 = the 40 the cards ride up + 22 of air above them.
            .padding(start = ClomniTheme.Space.xxl.dp, end = ClomniTheme.Space.xxl.dp, bottom = 62.dp),
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            BrandMark(header, theme)
            Spacer(Modifier.weight(1f))
            TeamAvatars(header.teamAvatars, theme)
            if (header.teamAvatars.isNotEmpty()) Spacer(Modifier.width(ClomniTheme.Space.l.dp))
            CloseButton(header.closeLabel, text, close)
        }
        Column(Modifier.padding(top = 20.dp).semantics(mergeDescendants = true) { heading() }) {
            val greeting = clomniText(
                ClomniTheme.FontSize.greeting,
                text,
                FontWeight.SemiBold,
                lineHeight = 1.22f,
                letterSpacing = -0.4f,
            )
            BasicText(header.greeting, Modifier.alpha(0.62f), style = greeting)
            BasicText(header.title, style = greeting)
        }
    }
}

/** The 22 dp white square with the logo (or the brand's initial) and the brand name 17/700. */
@Composable
private fun BrandMark(header: HomeScreen.Header, theme: ClomniTheme) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(ClomniTheme.Size.logo.dp)
                .clip(RoundedCornerShape(ClomniTheme.Radius.logo.dp))
                .background(Color.White)
                .clearAndSetSemantics {},
            Alignment.Center,
        ) {
            val logo = header.logoUrl
            if (logo != null && !LocalInspectionMode.current) {
                AsyncImage(logo, contentDescription = null, Modifier.padding(3.dp), contentScale = ContentScale.Fit)
            } else {
                val size = with(LocalDensity.current) { 13.dp.toSp() }
                BasicText(
                    header.brandInitial,
                    style = clomniText(13f, theme.colors.primary, FontWeight.Bold)
                        .copy(fontSize = size, lineHeight = size),
                )
            }
        }
        Spacer(Modifier.width(7.dp))
        BasicText(
            header.brandName,
            style = clomniText(
                ClomniTheme.FontSize.brand,
                theme.colors.onPrimary,
                FontWeight.Bold,
                lineHeight = 1.2f,
                letterSpacing = -0.2f,
            ),
            maxLines = 1,
        )
    }
}

/** Up to three 24 dp avatars overlapping by 7, each ringed in the header's colour. */
@Composable
private fun TeamAvatars(urls: List<String>, theme: ClomniTheme) {
    if (urls.isEmpty()) return
    val ring = 2.dp
    Row(
        Modifier.clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(-ClomniTheme.Size.headerAvatarOverlap.dp - ring * 2),
    ) {
        for (url in urls) {
            Box(Modifier.clip(CircleShape).background(theme.colors.primaryDark.color).padding(ring)) {
                Avatar(url, "", ClomniTheme.Size.headerAvatar, theme)
            }
        }
    }
}

/** Skeleton, error, or the cards the config asks for; switching fades (200 ms), nothing moves. */
@Composable
private fun HomeCards(screen: HomeScreen, theme: ClomniTheme, actions: MessengerActions, modifier: Modifier) {
    Crossfade(screen.phase, modifier, animationSpec = tween(200), label = "home") { phase ->
        Column(verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp)) {
            when (phase) {
                HomeScreen.Phase.LOADING -> {
                    SkeletonBlock(58f, theme)
                    SkeletonBlock(74f, theme)
                }
                HomeScreen.Phase.FAILED -> screen.failure?.let { FailureView(it, theme, actions.retry) }
                HomeScreen.Phase.READY -> {
                    screen.newConversation?.let { NewConversationCardView(it, theme, actions.newConversation) }
                    screen.recent?.let { RecentCardView(it, theme, actions.openConversation) }
                    screen.channels?.let { ChannelsCardView(it, theme) }
                }
            }
        }
    }
}
