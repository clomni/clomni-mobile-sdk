package ai.clomni.messenger.ui

import ai.clomni.messenger.R
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
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

/**
 * Home (DESIGN-PASS-2 1–6): no header block and no tab bar. The brand's colour starts at the top, from the top start
 * corner to a slightly lighter tone, and fades into the page by about 45% of the screen; the logo top start, ✕ top end,
 * the two-line greeting, then the cards on the fade: "Mesajlar" (the list), the latest conversation, "Bizə mesaj
 * göndərin", the channels, in the panel's order.
 */
@Composable
internal fun HomeView(screen: HomeScreen, theme: ClomniTheme, actions: MessengerActions) {
    Box(Modifier.fillMaxSize().background(theme.colors.background.color)) {
        // The full brand colour reaches 16 dp under the greeting, then fades into the page over 160 dp: the text
        // always stands on the full colour, and a larger title_scale takes the colour further down with it.
        var greetingBottom by remember { mutableStateOf(0f) }
        Column(
            Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .homeBackdrop(screen.header, theme, greetingBottom)
                .windowInsetsPadding(WindowInsets.statusBars),
        ) {
            HomeTop(screen.header, theme, actions.close)
            Greeting(screen.header, theme, Modifier.onGloballyPositioned { greetingBottom = it.boundsInParent().bottom })
            screen.offline?.let { OfflineStrip(it, theme) }
            HomeCards(
                screen,
                theme,
                actions,
                Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 24.dp),
            )
        }
    }
}

/** The light tone the brand colour runs to towards the top end: a quarter of the way to white. */
private fun lighter(color: RgbColor): RgbColor = RgbColor.WHITE.over(color, 0.25)

/**
 * Behind the scrolling page, from its top: the brand colour (header_from) running to a lighter tone diagonally
 * (gradient), or flat (solid), or the panel's picture under its veil (image), in full down to 16 dp under the
 * greeting ([greetingBottom], px); then the page's own colour rising over it for 160 dp, so it fades with no edge.
 */
@Composable
private fun Modifier.homeBackdrop(header: HomeScreen.Header, theme: ClomniTheme, greetingBottom: Float): Modifier {
    val picture = header.imageUrl.takeIf { header.style == MessengerConfig.HeaderStyle.IMAGE }
    val bitmap = picture?.let { LocalPreviewImages.current[it] }
    val painter = if (picture != null && bitmap == null && !LocalInspectionMode.current) {
        coil.compose.rememberAsyncImagePainter(
            ImageSizing.url(picture, ImageSizing.Kind.HEADER, LocalConfiguration.current.screenWidthDp.toFloat(), LocalDensity.current.density),
            ClomniImages.loader(LocalContext.current),
        )
    } else {
        null
    }
    val brand = theme.colors.headerFrom.color
    val light = lighter(theme.colors.headerFrom).color
    val page = theme.colors.background.color
    return drawBehind {
        val fadeStart = greetingBottom + 16.dp.toPx()
        val end = fadeStart + 160.dp.toPx()
        val area = Size(size.width, end)
        when {
            picture != null -> {
                drawRect(theme.colors.surface.color, size = area)
                if (bitmap != null) {
                    val scale = maxOf(area.width / bitmap.width, area.height / bitmap.height)
                    withTransform({ scale(scale, scale, Offset.Zero) }) { drawImage(bitmap) }
                } else if (painter != null) {
                    with(painter) { draw(area) }
                }
                drawRect(Brush.verticalGradient(listOf(VEIL_TOP, VEIL_BOTTOM), endY = end), size = area)
            }
            header.style == MessengerConfig.HeaderStyle.SOLID -> drawRect(brand, size = area)
            else -> drawRect(Brush.linearGradient(listOf(brand, light), Offset.Zero, Offset(size.width, end)), size = area)
        }
        drawRect(Brush.verticalGradient(listOf(page.copy(alpha = 0f), page), startY = fadeStart, endY = end), size = area)
    }
}

private val VEIL_TOP = Color.Black.copy(alpha = 0.35f)
private val VEIL_BOTTOM = Color.Black.copy(alpha = 0.55f)

/** The logo (or the written logo) at the top start, the team's faces and ✕ at the top end; one 48 dp row. */
@Composable
private fun HomeTop(header: HomeScreen.Header, theme: ClomniTheme, close: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().closeButtonPlace().heightIn(min = ClomniTheme.Size.touchTarget.dp).padding(start = HOME_START),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val wordmark = (if (theme.isDark) header.wordmarkDarkUrl else null) ?: header.wordmarkUrl
        if (wordmark != null) {
            Wordmark(wordmark, header, theme, Modifier.weight(1f))
        } else {
            Logo(header, theme, Modifier.weight(1f))
        }
        TeamAvatars(header.teamAvatars, theme.colors.headerFrom, theme)
        if (header.teamAvatars.isNotEmpty()) Spacer(Modifier.width(ClomniTheme.Space.l.dp))
        CloseButton(header.closeLabel, CloseStyle.ON_BRAND, theme, close)
    }
}

/** Where Home's logo, greeting and the cards' text start: the cards' 16 and their padding 20. */
private val HOME_START = 36.dp

/**
 * "Salam, Aysel" and "Necə kömək edə bilərik?", both 28 × the panel's title_scale (sp: the user's font size goes on
 * top), line height 1.2, about 80% of the screen wide, wrapping; both in header_text, the first semibold at 72%, the
 * second bold (coordinator's decision, 2026-10-03: primary_strong read blurred on a mid green).
 */
@Composable
private fun Greeting(header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier = Modifier) {
    val text = theme.colors.headerText
    val first = text.over(theme.colors.headerFrom, 0.72)
    Column(
        modifier.padding(start = HOME_START, top = 32.dp).fillMaxWidth(0.8f).semantics(mergeDescendants = true) { heading() },
    ) {
        val size = header.titleSize
        BasicText(header.greeting, style = clomniText(size, first, FontWeight.SemiBold, lineHeight = 1.2f, letterSpacing = -0.3f))
        BasicText(header.title, style = clomniText(size, text, FontWeight.Bold, lineHeight = 1.2f, letterSpacing = -0.3f))
    }
}

/**
 * The written logo (APPEARANCE-CONTRACT 4a): 32 dp × the panel's logo_scale high, at most 60% of the header's width, fitted, never cut or
 * stretched; its room is kept while it loads, and if it cannot load the logo and the name stand in. Read as the
 * brand's name. Home's header only: the conversation keeps the logo and the name.
 */
@Composable
private fun Wordmark(url: String, header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier) {
    var failed by remember(url) { mutableStateOf(false) }
    if (failed) return Logo(header, theme, modifier)
    val width = LocalConfiguration.current.screenWidthDp * 0.6f
    Box(modifier.semantics { contentDescription = header.brandName }, Alignment.CenterStart) {
        val box = Modifier.height(header.logoSize.dp).widthIn(max = width.dp).fillMaxWidth()
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
 * The logo as it was uploaded, 32 dp × the panel's logo_scale high with 8 dp corners and nothing around it (the dark-mode one in dark mode).
 * Without one the place stays empty: no initial (DESIGN-PASS-2 4).
 */
@Composable
private fun Logo(header: HomeScreen.Header, theme: ClomniTheme, modifier: Modifier = Modifier) {
    val logo = (if (theme.isDark) header.logoDarkUrl else null) ?: header.logoUrl
    Box(modifier) {
        if (logo != null) {
            val size = header.logoSize
            RemoteImage(
                logo,
                ImageSizing.Kind.ICON,
                size,
                theme.colors.primarySoft.color,
                Modifier.size(size.dp).clip(RoundedCornerShape(ClomniTheme.Radius.logo.dp)).semantics { contentDescription = header.brandName },
            )
        }
    }
}

/** Skeleton, error, or the cards the config asks for, in its order, 12 apart; switching fades (200 ms). */
@Composable
private fun HomeCards(screen: HomeScreen, theme: ClomniTheme, actions: MessengerActions, modifier: Modifier) {
    Crossfade(screen.phase, modifier, animationSpec = tween(200), label = "home") { phase ->
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (phase) {
                HomeScreen.Phase.LOADING -> {
                    SkeletonBlock(64f, theme)
                    SkeletonBlock(112f, theme)
                }
                HomeScreen.Phase.FAILED -> screen.failure?.let { FailureView(it, theme, actions.retry) }
                HomeScreen.Phase.READY -> {
                    for (card in screen.order) {
                        when (card) {
                            MessengerConfig.HomeCard.MESSAGES -> MessagesCard(screen.messagesCard, theme, actions.openMessages)
                            MessengerConfig.HomeCard.SEND ->
                                screen.newConversation?.let { SendCard(it, theme, actions.newConversation) }
                            MessengerConfig.HomeCard.RECENT -> screen.recent?.let { LatestCard(it, theme, actions.openConversation) }
                            MessengerConfig.HomeCard.CHANNELS -> screen.channels?.let { ChannelsCardView(it, theme) }
                            MessengerConfig.HomeCard.NEWS -> for (news in screen.news) NewsCardView(news, theme, actions.openNews)
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

/** A Home card's title: 17 semibold. */
@Composable
private fun cardTitle(theme: ClomniTheme) = clomniText(17f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.3f)

/** "Mesajlar" and the conversation icon: the list. A red dot while something is unread. */
@Composable
private fun MessagesCard(card: HomeScreen.MessagesCard, theme: ClomniTheme, open: () -> Unit) {
    Row(Modifier.fillMaxWidth().homeCard(theme, card.accessibilityLabel, open), verticalAlignment = Alignment.CenterVertically) {
        BasicText(card.title, Modifier.weight(1f), style = cardTitle(theme))
        if (card.unread) {
            Box(Modifier.size(ClomniTheme.Size.unreadDot.dp).clip(CircleShape).background(theme.colors.unread.color))
            Spacer(Modifier.width(ClomniTheme.Space.s.dp))
        }
        Icon(R.drawable.clomni_ic_chat_filled, theme.colors.textPrimary, 20.dp)
    }
}

/** "Bizə mesaj göndərin" and an arrow in the brand colour: a new conversation. */
@Composable
private fun SendCard(card: HomeScreen.NewConversationCard, theme: ClomniTheme, start: () -> Unit) {
    Row(Modifier.fillMaxWidth().homeCard(theme, card.accessibilityLabel, start), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            BasicText(card.title, style = cardTitle(theme))
            card.subtitle?.let {
                BasicText(it, Modifier.padding(top = 4.dp), style = clomniText(14f, theme.colors.textSecondary))
            }
        }
        Spacer(Modifier.width(ClomniTheme.Space.l.dp))
        Icon(R.drawable.clomni_ic_send, theme.colors.primaryText, 20.dp)
    }
}

/** "Son mesaj": the newest conversation, its avatar, who and when on one line, the message under it. */
@Composable
private fun LatestCard(card: HomeScreen.RecentCard, theme: ClomniTheme, open: (String) -> Unit) {
    val row = card.row
    Column(Modifier.fillMaxWidth().homeCard(theme, "${card.label}. ${row.accessibilityLabel}") { open(row.id) }) {
        BasicText(card.label, Modifier.padding(bottom = 12.dp), style = cardTitle(theme))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(row.avatarUrl, row.initial, 40f, theme)
            Spacer(Modifier.width(ClomniTheme.Space.l.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicText(
                        row.name,
                        Modifier.weight(1f, fill = false),
                        style = clomniText(15f, theme.colors.textPrimary, FontWeight.Medium),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.width(ClomniTheme.Space.s.dp))
                    BasicText(row.time, style = clomniText(14f, theme.colors.textSecondary), maxLines = 1)
                }
                BasicText(
                    row.preview,
                    style = clomniText(14f, if (row.unread) theme.colors.textPrimary else theme.colors.textSecondary),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (row.unread) {
                Spacer(Modifier.width(ClomniTheme.Space.s.dp))
                Box(Modifier.size(ClomniTheme.Size.unreadDot.dp).clip(CircleShape).background(theme.colors.unread.color))
            }
        }
    }
}
