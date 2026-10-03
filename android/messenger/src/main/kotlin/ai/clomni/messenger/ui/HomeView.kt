package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.protocol.MessengerConfig
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/** The Home tab (brief 8·7.3): the brand header with the greeting, and the cards riding up over it by 40. */
@Composable
internal fun HomeView(screen: HomeScreen, theme: ClomniTheme, actions: MessengerActions) {
    val scroll = rememberScrollState()
    var headerHeight by remember { mutableStateOf(0) }
    // Behind the page, the header's colour for its own height: pulled down past the top (overscroll), the header seems
    // to stretch and the page's grey never shows above it.
    val backdrop = Modifier.drawBehind {
        drawRect(theme.colors.headerFrom.color, size = Size(size.width, (headerHeight - scroll.value).coerceAtLeast(0).toFloat()))
    }
    Column(Modifier.fillMaxSize().background(theme.colors.canvas.color).then(backdrop).verticalScroll(scroll)) {
        Box(Modifier.onSizeChanged { headerHeight = it.height }) { HomeHeader(screen.header, theme, actions.close) }
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
                // 64 = the 40 the cards ride up + 24 of air above them.
                .padding(start = ClomniTheme.Space.xxl.dp, end = ClomniTheme.Space.l.dp, bottom = 64.dp),
        ) {
            // 48: the buttons' targets stay inside the row, whatever is above it.
            Row(Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp), verticalAlignment = Alignment.CenterVertically) {
                // The brand gives way (its name ends in "…"); the avatars and ✕ keep their size.
                val wordmark = (if (theme.isDark) header.wordmarkDarkUrl else null) ?: header.wordmarkUrl
                if (wordmark != null) {
                    Wordmark(wordmark, header, theme, Modifier.weight(1f))
                } else {
                    BrandMark(header, theme, Modifier.weight(1f))
                }
                Spacer(Modifier.width(ClomniTheme.Space.l.dp))
                TeamAvatars(header.teamAvatars, theme.colors.headerFrom, theme)
                if (header.teamAvatars.isNotEmpty()) Spacer(Modifier.width(ClomniTheme.Space.l.dp))
                // 12 dp from the screen's edge, like the avatars' row (the row's end padding).
                CloseButton(header.closeLabel, text, close, endRoom = ClomniTheme.Space.l.dp)
            }
            Column(Modifier.padding(top = 20.dp).semantics(mergeDescendants = true) { heading() }) {
                // Both lines in the header's full colour, set apart by size and weight (BRIEF-DEVIATIONS 18), at the
                // panel's title_size; sp, so the user's font size goes on top, and long text wraps.
                val size = header.titleSize
                BasicText(header.greeting, style = clomniText(size.firstLine, text, lineHeight = 1.25f))
                BasicText(header.title, style = clomniText(size.secondLine, text, FontWeight.SemiBold, lineHeight = 1.25f, letterSpacing = -0.3f))
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

/**
 * The written logo (APPEARANCE-CONTRACT 4a): 32 dp high, at most 60% of the header's width, fitted, never cut or
 * stretched; its room is kept while it loads, and if it cannot load the logo and the name stand in. Read as the
 * brand's name. Home's header only: the conversation keeps the logo and the name.
 */
@Composable
private fun Wordmark(url: String, header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier) {
    var failed by remember(url) { mutableStateOf(false) }
    if (failed) return BrandMark(header, theme, modifier)
    val width = LocalConfiguration.current.screenWidthDp * 0.6f
    Box(modifier.semantics { contentDescription = header.brandName }, Alignment.CenterStart) {
        val box = Modifier.height(32.dp).widthIn(max = width.dp).fillMaxWidth()
        val preview = LocalPreviewImages.current[url]
        when {
            preview != null -> Image(preview, null, box, alignment = Alignment.CenterStart, contentScale = ContentScale.Fit)
            LocalInspectionMode.current -> Box(box)
            else -> {
                val density = LocalDensity.current.density
                AsyncImage(
                    remember(url, density) { ImageSizing.url(url, ImageSizing.Kind.WORDMARK, width, density) },
                    contentDescription = null,
                    imageLoader = ClomniImages.loader(LocalContext.current),
                    modifier = box,
                    alignment = Alignment.CenterStart,
                    contentScale = ContentScale.Fit,
                    onError = { failed = true },
                )
            }
        }
    }
}

/**
 * The logo as it was uploaded, 32 dp with 8 dp corners and nothing around it (the dark-mode one in dark mode); without
 * one the brand's initial on a 32 dp circle of its soft tone. The name 17 semibold 10 dp away, both centred on one line.
 */
@Composable
private fun BrandMark(header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier = Modifier) {
    val logo = (if (theme.isDark) header.logoDarkUrl else null) ?: header.logoUrl
    // Before any config there is no brand yet: an empty circle would be a placeholder for nothing.
    if (logo == null && header.brandName.isBlank()) return Spacer(modifier)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        val size = ClomniTheme.Size.logo
        if (logo != null) {
            RemoteImage(
                logo,
                ImageSizing.Kind.ICON,
                size,
                theme.colors.primarySoft.color,
                Modifier.size(size.dp).clip(RoundedCornerShape(ClomniTheme.Radius.logo.dp)).clearAndSetSemantics {},
            )
        } else {
            Box(Modifier.size(size.dp).clip(CircleShape).background(theme.colors.primarySoft.color).clearAndSetSemantics {}, Alignment.Center) {
                val letter = with(LocalDensity.current) { 15.dp.toSp() }
                BasicText(
                    header.brandInitial,
                    style = clomniText(15f, theme.colors.primaryText, FontWeight.SemiBold).copy(fontSize = letter, lineHeight = letter),
                )
            }
        }
        Spacer(Modifier.width(ClomniTheme.Space.l.dp))
        BasicText(
            header.brandName,
            Modifier.weight(1f, fill = false),
            // The name grows with the user's font size up to 1.5 times, no more: it shares its row with the buttons.
            style = clomniText(ClomniTheme.FontSize.brand, theme.colors.headerText, FontWeight.SemiBold, lineHeight = 1.25f)
                .capFontScale(1.5f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
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
