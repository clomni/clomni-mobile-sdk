package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.protocol.MessengerConfig
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

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
    // header_text: white on a dark header or a picture, dark on a light one; never on_primary.
    val text = theme.colors.headerText
    Box(Modifier.fillMaxWidth().then(if (header.glow) Modifier.glow(theme) else Modifier)) {
        HeaderBackground(header, theme, Modifier.matchParentSize())
        Column(
            Modifier.fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                // 62 = the 40 the cards ride up + 22 of air above them.
                .padding(start = ClomniTheme.Space.xxl.dp, end = ClomniTheme.Space.xxl.dp, bottom = 62.dp),
        ) {
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
                BrandMark(header, theme)
                Spacer(Modifier.weight(1f))
                TeamAvatars(header.teamAvatars, theme.colors.headerFrom, theme)
                if (header.teamAvatars.isNotEmpty()) Spacer(Modifier.width(ClomniTheme.Space.l.dp))
                CloseButton(header.closeLabel, text, close)
            }
            Column(Modifier.padding(top = 20.dp).semantics(mergeDescendants = true) { heading() }) {
                // The first line in the header's full colour, set apart by size and weight rather than a 62% fade,
                // which read at about 2.2:1 on Apar's green (BRIEF-DEVIATIONS 18).
                BasicText(
                    header.greeting,
                    style = clomniText(ClomniTheme.FontSize.greetingFirstLine, text, lineHeight = 1.3f, letterSpacing = -0.2f),
                )
                BasicText(
                    header.title,
                    style = clomniText(ClomniTheme.FontSize.greeting, text, FontWeight.SemiBold, lineHeight = 1.22f, letterSpacing = -0.4f),
                )
            }
        }
    }
}

/**
 * The glow (APPEARANCE-CONTRACT 1): a soft radial light of the brand colour at 25% behind the header, so it shows
 * where it spills out under it, around the cards; as the panel's preview draws it: an ellipse 140% of the header's
 * width and 260 dp tall, from 45% of the header's height down.
 */
private fun Modifier.glow(theme: ClomniTheme): Modifier = drawBehind {
    val height = 260.dp.toPx()
    val center = Offset(size.width / 2, size.height * 0.45f + height / 2)
    val light = theme.colors.primary.color.copy(alpha = 0.25f)
    withTransform({ scale(scaleX = size.width * 1.4f / height, scaleY = 1f, pivot = center) }) {
        drawCircle(Brush.radialGradient(listOf(light, Color.Transparent), center, height / 2), height / 2, center)
    }
}

/**
 * Behind the header and the status bar: the brand gradient (header_from at the top to header_to; one colour when
 * solid), or the panel's picture under a black veil, 35% at the top to 55% at the bottom.
 */
@Composable
private fun HeaderBackground(header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier) {
    val picture = header.imageUrl.takeIf { header.style == MessengerConfig.HeaderStyle.IMAGE }
    Box(
        modifier.clearAndSetSemantics {}.drawWithContent {
            if (picture == null) {
                drawRect(Brush.verticalGradient(listOf(theme.colors.headerFrom.color, theme.colors.headerTo.color)))
            }
            drawContent()
            if (picture != null) drawRect(Brush.verticalGradient(listOf(VEIL_TOP, VEIL_BOTTOM)))
        },
    ) {
        if (picture != null) {
            RemoteImageFill(picture, ImageSizing.Kind.HEADER, LocalConfiguration.current.screenWidthDp.toFloat(), theme.colors.primarySoft.color)
        }
    }
}

private val VEIL_TOP = Color.Black.copy(alpha = 0.35f)
private val VEIL_BOTTOM = Color.Black.copy(alpha = 0.55f)

/** The 22 dp white square with the logo (the dark-mode one in dark mode) or the brand's initial, and the brand name 17/700. */
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
            val logo = (if (theme.isDark) header.logoDarkUrl else null) ?: header.logoUrl
            if (logo != null) {
                RemoteImage(
                    logo,
                    ImageSizing.Kind.ICON,
                    ClomniTheme.Size.logo,
                    theme.colors.primarySoft.color,
                    Modifier.fillMaxSize().padding(3.dp),
                    fit = true,
                )
            } else {
                val size = with(LocalDensity.current) { 13.dp.toSp() }
                BasicText(
                    header.brandInitial,
                    // On the white square in dark mode too, where the lighter primary would not read.
                    style = clomniText(13f, theme.colors.primary.readableOn(listOf(RgbColor.WHITE)), FontWeight.Bold)
                        .copy(fontSize = size, lineHeight = size),
                )
            }
        }
        Spacer(Modifier.width(7.dp))
        BasicText(
            header.brandName,
            style = clomniText(
                ClomniTheme.FontSize.brand,
                theme.colors.headerText,
                FontWeight.Bold,
                lineHeight = 1.2f,
                letterSpacing = -0.2f,
            ),
            maxLines = 1,
        )
    }
}

/** Skeleton, error, or the cards the config asks for, in its order; switching fades (200 ms), nothing moves. */
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
                    for (card in screen.order) {
                        when (card) {
                            MessengerConfig.HomeCard.SEND ->
                                screen.newConversation?.let { NewConversationCardView(it, theme, actions.newConversation) }
                            MessengerConfig.HomeCard.RECENT -> screen.recent?.let { RecentCardView(it, theme, actions.openConversation) }
                            MessengerConfig.HomeCard.CHANNELS -> screen.channels?.let { ChannelsCardView(it, theme) }
                        }
                    }
                    screen.poweredBy?.let {
                        BasicText(
                            it,
                            Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.s.dp),
                            style = clomniText(ClomniTheme.FontSize.meta, theme.colors.textSecondary).copy(textAlign = TextAlign.Center),
                        )
                    }
                }
            }
        }
    }
}
