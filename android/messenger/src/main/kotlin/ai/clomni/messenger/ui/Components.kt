package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChannelItem
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.ConversationRow
import ai.clomni.messenger.presentation.HomeScreen
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.RgbColor
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

private val target = ClomniTheme.Size.touchTarget.dp

/**
 * A tappable element read out as one button labelled [label]. Pressed, it highlights in its own [shape] (a pill, a
 * circle, a card's corners), [diameter] wide around the centre when the visible circle is smaller than the target.
 */
internal fun Modifier.button(label: String, shape: Shape = RectangleShape, diameter: Dp? = null, onClick: () -> Unit): Modifier =
    clickable(interactionSource = null, indication = ShapedIndication(shape, diameter), role = Role.Button, onClick = onClick)
        .clearAndSetSemantics { contentDescription = label }

/**
 * A round avatar: the picture when it loads; until then (or without one) the initial on grey, or primary_soft where
 * there is no initial (the team's avatars).
 */
@Composable
internal fun Avatar(url: String?, initial: String, size: Float, theme: ClomniTheme, modifier: Modifier = Modifier) {
    val circle = if (initial.isEmpty()) theme.colors.primarySoft else theme.colors.textSecondary
    Box(modifier.size(size.dp).clip(CircleShape).background(circle.color), Alignment.Center) {
        // Sized with the circle, not with the user's font scale.
        val fontSize: TextUnit = with(LocalDensity.current) { (size * 0.41f).dp.toSp() }
        // White on the light theme's grey, black on the dark theme's lighter one: 4.5:1 either way.
        val style = clomniText(0f, ClomniTheme.readableText(circle), FontWeight.SemiBold).copy(fontSize = fontSize, lineHeight = fontSize)
        BasicText(initial, style = style)
        if (url != null) RemoteImageFill(url, ImageSizing.Kind.ICON, size, Color.Transparent)
    }
}

/**
 * Up to three 24 dp avatars overlapping by 7, each in a 2 dp [ring] of the colour behind them. The ring is drawn
 * outside the layout, as the reference's box-shadow is: the stack is 58 dp wide.
 */
@Composable
internal fun TeamAvatars(urls: List<String>, ring: RgbColor, theme: ClomniTheme) {
    if (urls.isEmpty()) return
    val width = 2.dp
    Row(
        Modifier.bleed(width, width).clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(-ClomniTheme.Size.headerAvatarOverlap.dp - width * 2),
    ) {
        for (url in urls) {
            Box(Modifier.clip(CircleShape).background(ring.color).padding(width)) {
                Avatar(url, "", ClomniTheme.Size.headerAvatar, theme)
            }
        }
    }
}

/** A block in the brand's soft tone standing in for content while the first load runs (brief 8·7.5: no spinner). */
@Composable
internal fun SkeletonBlock(height: Float, theme: ClomniTheme) {
    Box(
        Modifier.fillMaxWidth().height(height.dp)
            .clip(RoundedCornerShape(ClomniTheme.Radius.card.dp))
            // primary_soft, as every placeholder (APPEARANCE-CONTRACT 4).
            .background(theme.colors.primarySoft.color)
            .clearAndSetSemantics {},
    )
}

/**
 * The thin strip under the header (DESIGN-PASS-3 C1): 32 high on the text colour at 6%, a small icon and "İnternet
 * yoxdur" in 13 text_muted, opening and closing in 200 ms; the screen under it stays as the cache has it. When the
 * connection is back it says [connected] ("Qoşuldu") for a second, then closes.
 */
@Composable
internal fun OfflineStrip(offline: String?, connected: String, theme: ClomniTheme) {
    var back by remember { mutableStateOf(false) }
    var wasOffline by remember { mutableStateOf(offline != null) }
    LaunchedEffect(offline != null) {
        if (offline != null) {
            wasOffline = true
            back = false
        } else if (wasOffline) {
            wasOffline = false
            back = true
            delay(1_000)
            back = false
        }
    }
    AnimatedVisibility(
        offline != null || back,
        enter = expandVertically(tween(200)) + fadeIn(tween(200)),
        exit = shrinkVertically(tween(200)) + fadeOut(tween(200)),
    ) {
        val muted = theme.colors.textSecondary
        Row(
            Modifier.fillMaxWidth().heightIn(min = 32.dp)
                .background(theme.colors.textPrimary.color.copy(alpha = 0.06f))
                .padding(horizontal = ClomniTheme.Space.l.dp)
                .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                painterResource(if (offline != null) R.drawable.clomni_ic_offline else R.drawable.clomni_ic_check),
                null,
                Modifier.size(14.dp),
                colorFilter = ColorFilter.tint(muted.color),
            )
            Spacer(Modifier.width(6.dp))
            BasicText(offline ?: connected, style = clomniText(13f, muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** "Nəsə səhv getdi" with "Yenidən cəhd et". */
@Composable
internal fun FailureView(failure: HomeScreen.Failure, theme: ClomniTheme, retry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clomniCard(theme),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp),
    ) {
        val message = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary).copy(textAlign = TextAlign.Center)
        BasicText(failure.message, style = message)
        Box(
            Modifier.heightIn(min = target).button(failure.retry, RoundedCornerShape(ClomniTheme.Radius.card.dp), onClick = retry)
                .padding(horizontal = ClomniTheme.Space.l.dp),
            Alignment.Center,
        ) {
            val retryStyle = clomniText(ClomniTheme.FontSize.text, theme.colors.primaryText, FontWeight.SemiBold)
            BasicText(failure.retry, style = retryStyle)
        }
    }
}

/** Where a [CloseButton] sits, for its circle's colour. */
internal enum class CloseStyle {
    /** On Home's brand colour: a white circle at 55%, the ✕ dark. */
    ON_BRAND,

    /** On the white (or dark) background: the text colour at 6%, the ✕ in the text colour. */
    ON_SURFACE,

    /** Over a picture on black: white at 20%, the ✕ white. */
    ON_MEDIA,
}

/**
 * ✕, the same on every screen (DESIGN-PASS-2 6): a 40 dp circle with a 20 dp cross drawn 2 dp thick, in a 48 dp
 * target. Placed by [closeButtonPlace] or [TopBar]: 16 dp from the end edge and 12 under the safe area.
 */
@Composable
internal fun CloseButton(label: String, style: CloseStyle, theme: ClomniTheme, close: () -> Unit, modifier: Modifier = Modifier) =
    CircleButton(label, style, theme, close, modifier) { cross ->
        // The cross fills a 20 dp square: each arm runs 10 dp from the centre along a diagonal.
        val arm = 10.dp.toPx() / 1.414f
        val stroke = 2.dp.toPx()
        drawLine(cross, Offset(center.x - arm, center.y - arm), Offset(center.x + arm, center.y + arm), stroke, StrokeCap.Round)
        drawLine(cross, Offset(center.x - arm, center.y + arm), Offset(center.x + arm, center.y - arm), stroke, StrokeCap.Round)
    }

/** A 40 dp circle in [style]'s colour with [glyph] drawn in its ink, in a 48 dp target: ✕ and back. */
@Composable
internal fun CircleButton(
    label: String,
    style: CloseStyle,
    theme: ClomniTheme,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    glyph: DrawScope.(Color) -> Unit,
) {
    val (circle, ink) = when (style) {
        CloseStyle.ON_BRAND -> Color.White.copy(alpha = 0.55f) to RgbColor.parse("#1B1D21")!!.color
        CloseStyle.ON_SURFACE -> theme.colors.textPrimary.color.copy(alpha = 0.06f) to theme.colors.textPrimary.color
        CloseStyle.ON_MEDIA -> Color.White.copy(alpha = 0.2f) to Color.White
    }
    Box(modifier.size(target).button(label, CircleShape, CLOSE_CIRCLE, onClick), Alignment.Center) {
        Canvas(Modifier.size(CLOSE_CIRCLE)) {
            drawCircle(circle)
            glyph(ink)
        }
    }
}

/** The close button's circle. */
internal val CLOSE_CIRCLE = 40.dp

/**
 * The close button's place on a screen: the circle 16 dp from the end edge and 12 dp under the safe area (the target
 * reaches 4 dp around the circle).
 */
internal fun Modifier.closeButtonPlace(): Modifier = padding(top = 12.dp - 4.dp, end = 16.dp - 4.dp)

/** A drawable icon tinted in one colour. */
@Composable
internal fun Icon(id: Int, color: RgbColor, size: Dp, modifier: Modifier = Modifier) {
    Image(painterResource(id), null, modifier.size(size), colorFilter = ColorFilter.tint(color.color))
}

/** "Bizə mesaj göndərin", the reply time, and the paper plane in the brand colour. */
@Composable
internal fun NewConversationCardView(card: HomeScreen.NewConversationCard, theme: ClomniTheme, start: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clomniCard(theme, card.accessibilityLabel, start),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            val title = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary, FontWeight.SemiBold)
            BasicText(card.title, style = title)
            card.subtitle?.let {
                val subtitle = clomniText(ClomniTheme.FontSize.secondary, theme.colors.textSecondary)
                BasicText(it, Modifier.padding(top = 1.dp), style = subtitle)
            }
        }
        Spacer(Modifier.width(ClomniTheme.Space.l.dp))
        Icon(R.drawable.clomni_ic_send, theme.colors.primary, 18.dp)
    }
}

/** Avatar 28, the message on one line (13), "Ad · vaxt" (12.5, grey), and the red unread dot 7. */
@Composable
internal fun ConversationRowView(row: ConversationRow, theme: ClomniTheme) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(row.avatarUrl, row.initial, ClomniTheme.Size.avatar, theme)
        Spacer(Modifier.width(ClomniTheme.Space.m.dp))
        Column(Modifier.weight(1f)) {
            BasicText(
                row.preview,
                style = clomniText(ClomniTheme.FontSize.preview, theme.colors.textPrimary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            BasicText(
                row.detail,
                style = clomniText(ClomniTheme.FontSize.secondary, theme.colors.textSecondary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (row.unread) {
            Spacer(Modifier.width(ClomniTheme.Space.m.dp))
            Box(Modifier.size(ClomniTheme.Size.unreadDot.dp).clip(CircleShape).background(theme.colors.unread.color))
        }
    }
}

/** "Bizi izləyin": 30 dp squares (radius 8) in each platform's colour, 20 dp apart in 48 dp targets. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ChannelsCardView(card: HomeScreen.ChannelsCard, theme: ClomniTheme) {
    val uriHandler = LocalUriHandler.current
    Column(Modifier.fillMaxWidth().clomniCard(theme)) {
        BasicText(
            card.label,
            Modifier.padding(bottom = ClomniTheme.Space.s.dp).semantics { heading() },
            style = clomniText(ClomniTheme.FontSize.label, theme.colors.textPrimary, FontWeight.SemiBold),
        )
        // The 30 dp squares 20 apart: their 48 dp targets side by side, none covering its neighbour; a long list wraps.
        val bleed = (target - ClomniTheme.Size.channel.dp) / 2
        val gap = Arrangement.spacedBy(ClomniTheme.Space.xxl.dp - bleed * 2)
        FlowRow(Modifier.bleed(bleed, bleed), horizontalArrangement = gap, verticalArrangement = gap) {
            for (item in card.items) {
                ChannelButton(item, theme) { runCatching { uriHandler.openUri(item.url) } }
            }
        }
    }
}

@Composable
private fun ChannelButton(item: ChannelItem, theme: ClomniTheme, open: () -> Unit) {
    val (background, mark) = when (val tint = item.tint) {
        is ChannelItem.Tint.Brand -> tint.color.color to RgbColor.WHITE
        ChannelItem.Tint.Neutral -> theme.colors.surface.color to theme.colors.textPrimary
    }
    Box(
        Modifier.size(target).button(item.accessibilityLabel, RoundedCornerShape(ClomniTheme.Radius.channel.dp), ClomniTheme.Size.channel.dp, open),
        Alignment.Center,
    ) {
        Box(
            Modifier.size(ClomniTheme.Size.channel.dp)
                .clip(RoundedCornerShape(ClomniTheme.Radius.channel.dp))
                .background(background),
            Alignment.Center,
        ) {
            val brand = item.tint is ChannelItem.Tint.Brand || item.icon == ChannelItem.Icon.X
            Icon(item.icon.drawable, mark, if (brand) 16.dp else 18.dp)
        }
    }
}

internal val ChannelItem.Icon.drawable: Int
    get() = when (this) {
        ChannelItem.Icon.INSTAGRAM -> R.drawable.clomni_brand_instagram
        ChannelItem.Icon.WHATSAPP -> R.drawable.clomni_brand_whatsapp
        ChannelItem.Icon.TELEGRAM -> R.drawable.clomni_brand_telegram
        ChannelItem.Icon.FACEBOOK -> R.drawable.clomni_brand_facebook
        ChannelItem.Icon.MESSENGER -> R.drawable.clomni_brand_messenger
        ChannelItem.Icon.LINKEDIN -> R.drawable.clomni_brand_linkedin
        ChannelItem.Icon.YOUTUBE -> R.drawable.clomni_brand_youtube
        ChannelItem.Icon.TIKTOK -> R.drawable.clomni_brand_tiktok
        ChannelItem.Icon.X -> R.drawable.clomni_brand_x
        ChannelItem.Icon.EMAIL -> R.drawable.clomni_ic_mail
        ChannelItem.Icon.PHONE -> R.drawable.clomni_ic_call
        ChannelItem.Icon.LINK -> R.drawable.clomni_ic_link
    }
