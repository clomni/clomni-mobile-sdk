package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ChatAvatar
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.Media
import ai.clomni.messenger.presentation.RatingCard
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.SystemLine
import ai.clomni.messenger.presentation.TextRun
import ai.clomni.messenger.presentation.TypingLine
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.layout.IntrinsicMeasurable
import androidx.compose.ui.layout.IntrinsicMeasureScope
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.MeasureResult
import androidx.compose.ui.layout.MeasureScope
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.sin

/** What the transcript hands back. */
internal class ChatActions(
    val back: () -> Unit = {},
    val close: () -> Unit = {},
    val send: () -> Unit = {},
    val pickImage: () -> Unit = {},
    /** Null when the app may not use the camera: the sheet has no camera row then. */
    val pickCamera: (() -> Unit)? = null,
    val pickFile: () -> Unit = {},
    /** The × on a picked file, before it is sent. */
    val removePicked: () -> Unit = {},
    val startNew: () -> Unit = {},
    val tap: (buttonId: String, messageId: String) -> Unit = { _, _ -> },
    /** The errors to show by field; empty when the form went. */
    val submit: (messageId: String, values: Map<String, String>) -> Map<String, String> = { _, _ -> emptyMap() },
    /** A rating's score, and its comment if any. */
    val rate: (messageId: String, score: Int, comment: String?) -> Unit = { _, _, _ -> },
    val retry: (clientId: String) -> Unit = {},
    /** "Yenidən cəhd et" after a failed first load. */
    val retryLoad: () -> Unit = {},
    val openImage: (url: String) -> Unit = {},
    val reachedTop: () -> Unit = {},
    /** A swipe or "Cavabla": the message to quote over the field. */
    val reply: (messageId: String) -> Unit = {},
    /** The ✕ on the quote over the field. */
    val cancelReply: () -> Unit = {},
)

/** Where a link in a message goes: `Clomni.onLink` first, then the system. The messenger's activity sets it. */
internal val LocalOpenLink = staticCompositionLocalOf<((String) -> Unit)?> { null }

/** Opens a message's link; an app that cannot open a tel: or mailto: link must not crash the conversation. */
@Composable
internal fun linkOpener(): (String) -> Unit {
    val uriHandler = LocalUriHandler.current
    val open = LocalOpenLink.current
    return { url -> runCatching { open?.invoke(url) ?: uriHandler.openUri(url) } }
}

/** The styled runs as one text: bold and italic spans; links underlined and tappable (see [TextRun.link]). */
@Composable
internal fun attributedText(runs: List<TextRun>, linkColor: RgbColor): AnnotatedString {
    val open = linkOpener()
    return buildAnnotatedString {
        for (run in runs) {
            val style = SpanStyle(
                fontWeight = if (run.bold) FontWeight.Bold else null,
                fontStyle = if (run.italic) FontStyle.Italic else null,
            )
            val link = run.link
            if (link == null) {
                withStyle(style) { append(run.text) }
            } else {
                val styles = TextLinkStyles(SpanStyle(color = linkColor.color, textDecoration = TextDecoration.Underline))
                withLink(LinkAnnotation.Url(link, styles) { open(link) }) {
                    withStyle(style) { append(run.text) }
                }
            }
        }
    }
}

/** True when the system's animations are off ("Remove animations"): new messages only fade in. */
@Composable
internal fun reduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) { Motion.reduced(context) }
}

@Composable
internal fun ChatItemView(item: ChatItem, theme: ClomniTheme, actions: ChatActions) {
    when (item) {
        is ChatItem.TimeItem -> BasicText(
            item.text,
            Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.xl.dp),
            style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary).copy(textAlign = TextAlign.Center),
        )
        is ChatItem.BubbleItem -> BubbleRow(item.bubble, theme, actions)
        is ChatItem.SystemItem -> SystemLineView(item.line, theme)
        is ChatItem.RepliesItem -> QuickRepliesView(item.block, theme) { buttonId -> actions.tap(buttonId, item.block.messageId) }
        is ChatItem.TypingItem -> TypingRow(item.line, theme)
    }
}

/** How a new item of the transcript comes in (M3, M4); the choices come in by themselves (M5). */
internal val ChatItem.arrival: Motion.Arrival?
    get() = when (this) {
        is ChatItem.BubbleItem -> if (bubble.side == Bubble.Side.INCOMING) Motion.Arrival.INCOMING else Motion.Arrival.OUTGOING
        is ChatItem.TypingItem -> Motion.Arrival.TYPING
        is ChatItem.RepliesItem -> null
        else -> Motion.Arrival.FADE
    }

/** 18 dp, 5 where bubbles of one run meet; the user's always keep the 5 dp bottom-end corner. */
internal fun Bubble.shape(): RoundedCornerShape {
    val round = ClomniTheme.Radius.message.dp
    val joined = ClomniTheme.Radius.messageJoined.dp
    val joinsAbove = position == Bubble.Position.MIDDLE || position == Bubble.Position.LAST
    val joinsBelow = position == Bubble.Position.FIRST || position == Bubble.Position.MIDDLE
    return if (side == Bubble.Side.INCOMING) {
        RoundedCornerShape(
            topStart = if (joinsAbove) joined else round,
            topEnd = round,
            bottomEnd = round,
            bottomStart = if (joinsBelow) joined else round,
        )
    } else {
        RoundedCornerShape(topStart = round, topEnd = if (joinsAbove) joined else round, bottomEnd = joined, bottomStart = round)
    }
}

/**
 * A bubble with its avatar slot (28, next to the last of a run), the author over the first of a run (13 medium), its
 * time and the user's mark inside it at the bottom end (G7), a failure under it, on its side of the screen. Bubbles of a run are 4 apart, runs 16. A bubble
 * is at most 78% of the screen wide (DESIGN-PASS-2 13, DESIGN-PASS-3 B2).
 */
@Composable
internal fun BubbleRow(bubble: Bubble, theme: ClomniTheme, actions: ChatActions) {
    val incoming = bubble.side == Bubble.Side.INCOMING
    val startsRun = bubble.position == Bubble.Position.FIRST || bubble.position == Bubble.Position.SINGLE
    val top = if (startsRun) ClomniTheme.Space.xl.dp else ClomniTheme.Space.xxs.dp
    val maxWidth = LocalConfiguration.current.screenWidthDp.dp * 0.78f
    val gutter = ClomniTheme.Size.avatar.dp + ClomniTheme.Space.s.dp
    val links = LocalTranscript.current
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    // A quote led here: the row glows in the brand colour for a second.
    val glow by animateColorAsState(
        if (links.highlighted == bubble.id) theme.colors.primary.color.copy(alpha = 0.12f) else Color.Transparent,
        tween(if (links.highlighted == bubble.id) 200 else 700),
        label = "quoted",
    )
    var menu by remember { mutableStateOf(false) }
    val swipe = remember { ReplySwipe() }
    val messageId = bubble.messageId
    val replyable = bubble.replyable && messageId != null
    val longPress: (() -> Unit)? = if (bubble.hasMenu) {
        {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            menu = true
        }
    } else {
        null
    }
    // TalkBack has no long press on a bubble: the menu's two actions are its own.
    val a11y = listOfNotNull(
        if (replyable) CustomAccessibilityAction(links.replyLabel) { actions.reply(messageId!!); true } else null,
        bubble.copyText?.let { text -> CustomAccessibilityAction(links.copyLabel) { copyText(context, text); true } },
    )
    Box(Modifier.fillMaxWidth().padding(top = top).background(glow, RoundedCornerShape(12.dp))) {
        if (incoming && replyable) ReplyArrow(swipe, theme, Modifier.align(Alignment.CenterStart))
        Column(
            Modifier.fillMaxWidth().swipeToReply(replyable, swipe) { messageId?.let(actions.reply) },
            horizontalAlignment = if (incoming) Alignment.Start else Alignment.End,
        ) {
            BubbleColumn(bubble, theme, actions, incoming, gutter, maxWidth, swipe.takeIf { replyable }, longPress, a11y)
            if (menu) MessageMenu(bubble, theme, actions.reply) { menu = false }
        }
    }
}

/** Who, the avatar slot, the bubble, then a failure: the parts of a [BubbleRow] that move with a swipe. */
@Composable
private fun BubbleColumn(
    bubble: Bubble,
    theme: ClomniTheme,
    actions: ChatActions,
    incoming: Boolean,
    gutter: Dp,
    maxWidth: Dp,
    swipe: ReplySwipe?,
    longPress: (() -> Unit)?,
    a11y: List<CustomAccessibilityAction>,
) {
    bubble.author?.let { author ->
        BasicText(
            author,
            Modifier.padding(start = gutter, bottom = 4.dp).clearAndSetSemantics {},
            style = clomniText(13f, theme.colors.textSecondary, FontWeight.Medium),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
    Row(verticalAlignment = Alignment.Bottom) {
        if (incoming) {
            val avatar = bubble.avatar
            if (avatar != null) {
                ChatAvatarView(avatar, ClomniTheme.Size.avatar, theme)
            } else {
                Spacer(Modifier.width(ClomniTheme.Size.avatar.dp))
            }
            Spacer(Modifier.width(ClomniTheme.Space.s.dp))
        }
        Box(Modifier.widthIn(max = maxWidth)) {
            if (!incoming && swipe != null) ReplyArrow(swipe, theme, Modifier.align(Alignment.CenterStart).offset(x = (-36).dp))
            BubbleBody(bubble, theme, actions, longPress, a11y)
        }
    }
    bubble.status?.takeIf { it.mark == null }?.let { FailureLine(it, theme, actions.retry) }
}

/** The bubble itself: text, image, file card or form; a quote at its top when it answers a message. */
@Composable
private fun BubbleBody(bubble: Bubble, theme: ClomniTheme, actions: ChatActions, longPress: (() -> Unit)?, a11y: List<CustomAccessibilityAction>) {
    val incoming = bubble.side == Bubble.Side.INCOMING
    val fill = if (incoming) theme.colors.surface else theme.colors.primary
    val ink = if (incoming) theme.colors.textPrimary else theme.colors.onPrimary
    val shape = bubble.shape()
    val quote = bubble.quote
    // H4: on_primary at 65% on the user's bubble, text_muted on the others'.
    val metaInk = if (incoming) theme.colors.textSecondary else theme.colors.onPrimary.over(fill, META_OPACITY.toDouble())
    val meta: @Composable (RgbColor?) -> Unit = { over -> BubbleMeta(bubble, over ?: metaInk, over ?: ink) }
    val open = linkOpener()
    when (val body = bubble.body) {
        // With a quote the bubble is as wide as the wider of the two, and the time goes to its bottom end (as WhatsApp).
        is Bubble.TextBody -> Column(
            Modifier.then(if (quote != null) Modifier.width(IntrinsicSize.Max) else Modifier)
                .clip(shape)
                .background(fill.color)
                .then(if (longPress != null) Modifier.longPressOverLinks(longPress) else Modifier)
                .padding(top = if (quote != null) 6.dp else 10.dp, bottom = META_BOTTOM, start = if (quote != null) 6.dp else 14.dp, end = if (quote != null) 6.dp else 14.dp),
        ) {
            if (quote != null) QuoteBlock(quote, ink, !incoming, Modifier.padding(bottom = 4.dp))
            TimedText(
                attributedText(body.runs, if (incoming) theme.colors.primaryText else theme.colors.onPrimary),
                clomniText(ClomniTheme.FontSize.message, ink),
                if (quote != null) Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp) else Modifier,
                Modifier.clearAndSetSemantics {
                    contentDescription = bubble.accessibilityLabel
                    // TalkBack reads the bubble as one text: each link is an action of its own.
                    val actions = a11y + body.runs.mapNotNull { run ->
                        run.link?.let { link -> CustomAccessibilityAction(run.text) { open(link); true } }
                    }
                    if (actions.isNotEmpty()) customActions = actions
                },
            ) { meta(null) }
        }
        is RatingCard -> RatingCardView(body, theme) { score, comment -> actions.rate(body.messageId, score, comment) }
        is Bubble.ImageBody -> Quoted(quote, shape, fill, ink, !incoming) {
            ImageBubble(body, bubble.accessibilityLabel, theme, fill, ink, actions.openImage, longPress, a11y, meta)
        }
        is Bubble.FileBody -> Quoted(quote, shape, fill, ink, !incoming) {
            val uriHandler = LocalUriHandler.current
            FileCard(
                body,
                ink,
                { meta(null) },
                Modifier.clip(shape).background(fill.color)
                    .combinedClickable(enabled = body.url != null || longPress != null, role = Role.Button, onLongClick = longPress) {
                        body.url?.let { runCatching { uriHandler.openUri(it) } }
                    }
                    .clearAndSetSemantics {
                        contentDescription = bubble.accessibilityLabel
                        role = Role.Button
                        if (a11y.isNotEmpty()) customActions = a11y
                    },
            )
        }
        is ai.clomni.messenger.presentation.FormCard -> FormCardView(
            body,
            theme,
            Modifier.clip(shape).background(fill.color),
        ) { values -> actions.submit(body.messageId, values) }
    }
}

/**
 * A long press on a bubble, on its links too (a link takes the touch's down, so it is not required unconsumed). The rest
 * of the touch is taken before the link sees it (the initial pass): holding a link opens the menu and not the link.
 */
private fun Modifier.longPressOverLinks(longPress: () -> Unit): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        awaitLongPressOrCancellation(down.id) ?: return@awaitEachGesture
        longPress()
        do {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            event.changes.forEach { it.consume() }
        } while (event.changes.any { it.pressed })
    }
}

/** An image or file that answers a message: the quote over it, both in one bubble of its colour. */
@Composable
private fun Quoted(quote: Bubble.Quote?, shape: Shape, fill: RgbColor, ink: RgbColor, outgoing: Boolean, content: @Composable () -> Unit) {
    if (quote == null) return content()
    Column(Modifier.width(IntrinsicSize.Max).clip(shape).background(fill.color).padding(4.dp)) {
        QuoteBlock(quote, ink, outgoing, Modifier.fillMaxWidth().padding(2.dp))
        Spacer(Modifier.height(4.dp))
        content()
    }
}

/**
 * An image in its reserved box (radius 12, brief 8·7.4), the caption under it; a tap opens it full screen. A size the
 * message does not give is a 4:3 placeholder until the picture is here, then the picture's own ratio.
 */
@Composable
private fun ImageBubble(
    image: Bubble.ImageBody,
    label: String,
    theme: ClomniTheme,
    fill: RgbColor,
    ink: RgbColor,
    open: (String) -> Unit,
    longPress: (() -> Unit)?,
    a11y: List<CustomAccessibilityAction>,
    meta: @Composable (RgbColor?) -> Unit,
) {
    val shape = RoundedCornerShape(ClomniTheme.Radius.card.dp)
    // Previews and screenshot tests load nothing (and have no loader to load with).
    val model: Any? = if (LocalInspectionMode.current) null else image.localFile ?: image.url
    val painter = model?.let { rememberAsyncImagePainter(it, ClomniImages.loader(LocalContext.current)) }
    val loaded = (painter?.state as? AsyncImagePainter.State.Success)?.painter?.intrinsicSize
    var width = image.width
    var height = image.height
    if (!image.sizeKnown && loaded != null && loaded.width > 0 && loaded.height > 0) {
        val box = Media.imageBox(loaded.width.toInt(), loaded.height.toInt())
        width = box.width
        height = box.height
    }
    val target = image.fullUrl ?: image.url
    Column(
        Modifier.clip(shape)
            .combinedClickable(enabled = target != null || longPress != null, role = Role.Button, onLongClick = longPress) { target?.let(open) }
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Image
                if (a11y.isNotEmpty()) customActions = a11y
            },
    ) {
        // A grey place of the bubble's size until the picture is here (DESIGN-PASS 5).
        Box(Modifier.size(width.dp, height.dp).background(theme.colors.surface.color)) {
            if (painter != null) {
                Image(painter, null, Modifier.size(width.dp, height.dp), contentScale = ContentScale.Crop)
                // The bubble's grey place and the indicator until the picture is here.
                LoadingSpinner(
                    painter.state is AsyncImagePainter.State.Loading,
                    theme.colors.primary,
                    "",
                    Modifier.align(Alignment.Center),
                )
            }
            // No caption: the time on the picture, white on a dark capsule (G7).
            if (image.caption == null) {
                Box(
                    Modifier.align(Alignment.BottomEnd).padding(6.dp)
                        .background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(50))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) { meta(RgbColor.WHITE) }
            }
        }
        image.caption?.let { caption ->
            TimedText(
                attributedText(caption, ink),
                clomniText(ClomniTheme.FontSize.text, ink),
                Modifier.width(width.dp).background(fill.color)
                    .padding(top = ClomniTheme.Space.s.dp, bottom = META_BOTTOM, start = ClomniTheme.Space.l.dp, end = ClomniTheme.Space.l.dp),
            ) { meta(null) }
        }
    }
}

internal val Media.FileIcon.drawable: Int
    get() = when (this) {
        Media.FileIcon.PDF -> R.drawable.clomni_ic_file_pdf
        Media.FileIcon.IMAGE -> R.drawable.clomni_ic_file_image
        Media.FileIcon.AUDIO -> R.drawable.clomni_ic_file_audio
        Media.FileIcon.VIDEO -> R.drawable.clomni_ic_file_video
        Media.FileIcon.DOCUMENT -> R.drawable.clomni_ic_file
    }

/** Icon, name (middle-truncated), size; the time under them at the end. */
@Composable
private fun FileCard(file: Bubble.FileBody, ink: RgbColor, meta: @Composable () -> Unit, modifier: Modifier) {
    Column(
        modifier.widthIn(max = 222.dp)
            .padding(top = ClomniTheme.Space.m.dp, bottom = META_BOTTOM, start = ClomniTheme.Space.l.dp, end = ClomniTheme.Space.l.dp),
        horizontalAlignment = Alignment.End,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(28.dp), Alignment.Center) { Icon(file.icon.drawable, ink, 22.dp) }
            Spacer(Modifier.width(ClomniTheme.Space.m.dp))
            Column(Modifier.weight(1f, fill = false)) {
                BasicText(
                    file.name,
                    style = clomniText(ClomniTheme.FontSize.text, ink, FontWeight.Medium),
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                BasicText(file.size, Modifier.alpha(0.7f), style = clomniText(ClomniTheme.FontSize.label, ink))
            }
        }
        meta()
    }
}

/** A failure under the user's message, in red words; tapped, it sends again. */
@Composable
private fun FailureLine(status: Bubble.Status, theme: ClomniTheme, retry: (String) -> Unit) {
    val style = clomniText(ClomniTheme.FontSize.meta, theme.colors.errorText)
    val retryId = status.retryId
    if (retryId == null) {
        BasicText(status.text, Modifier.padding(top = ClomniTheme.Space.xxs.dp), style = style)
    } else {
        // The 15 dp line reaches a 48 dp target without moving anything.
        val reach = 16.dp
        BasicText(
            status.text,
            Modifier.padding(top = ClomniTheme.Space.xxs.dp).bleed(vertical = reach).button(status.text) { retry(retryId) }.padding(vertical = reach),
            style = style,
        )
    }
}

/**
 * Inside the bubble, at its bottom end (G7, H4 as WhatsApp): the time, 11 and growing with the font size only up to 13,
 * and on the user's message its thin mark after it: the clock, then ✓, then ✓✓ riding on each other once read, at 65%
 * and at 100% once read. No words on screen, TalkBack reads "Göndərildi".
 */
@Composable
private fun BubbleMeta(bubble: Bubble, ink: RgbColor, markInk: RgbColor) {
    val time = bubble.time ?: return
    val status = bubble.status?.takeIf { it.mark != null }
    val scale = LocalDensity.current.fontScale
    val size = minOf(ClomniTheme.FontSize.meta * scale, META_MAX_SIZE) / scale
    Row(
        Modifier.clearAndSetSemantics { status?.let { contentDescription = it.text } },
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(time, style = clomniText(size, ink, lineHeight = 1.2f))
        val mark = status?.mark ?: return@Row
        // The clock becomes ✓ in place: only the icon cross-fades, nothing moves (M3, 150 ms).
        Crossfade(mark, animationSpec = tween(150), label = "status") { shown ->
            val (icon, width, height) = when (shown) {
                Bubble.Status.Mark.SENDING -> Triple(R.drawable.clomni_ic_clock, 9.dp, 9.dp)
                Bubble.Status.Mark.SENT -> Triple(R.drawable.clomni_ic_tick, 11.dp, 8.dp)
                Bubble.Status.Mark.READ -> Triple(R.drawable.clomni_ic_check_double, 15.dp, 8.dp)
            }
            val opacity = if (shown == Bubble.Status.Mark.READ) 1f else META_OPACITY
            Image(
                painterResource(icon),
                null,
                Modifier.size(width, height),
                colorFilter = ColorFilter.tint(markInk.color.copy(alpha = opacity)),
            )
        }
    }
}

/**
 * Text with the bubble's time at its bottom end (G7, as WhatsApp): on the text's last line when there is room for it
 * there, otherwise on a line of its own under it.
 */
@Composable
private fun TimedText(
    text: AnnotatedString,
    style: TextStyle,
    modifier: Modifier = Modifier,
    textModifier: Modifier = Modifier,
    meta: @Composable () -> Unit,
) {
    // Written while the text is measured, read right after: no state, so no second pass.
    val laidOut = remember { arrayOfNulls<TextLayoutResult>(1) }
    Layout({
        BasicText(text, textModifier, style = style, onTextLayout = { laidOut[0] = it })
        meta()
    }, modifier, remember { TimedTextPolicy(laidOut) })
}

/**
 * [TimedText]'s layout. Its intrinsic width counts the time beside the text, so a bubble as wide as the wider of a quote
 * and its text (`IntrinsicSize.Max`) keeps room for the time on the text's line.
 */
private class TimedTextPolicy(private val laidOut: Array<TextLayoutResult?>) : MeasurePolicy {
    override fun MeasureScope.measure(measurables: List<Measurable>, constraints: Constraints): MeasureResult {
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val words = measurables[0].measure(loose)
        val time = measurables.getOrNull(1)?.measure(loose)
        val result = laidOut[0]
        val drop = META_DROP.roundToPx()
        if (time == null || time.width == 0 || result == null) {
            return layout(words.width, words.height + drop) { words.placeRelative(0, 0) }
        }
        val last = result.lineCount - 1
        val lastLine = ceil(result.getLineRight(last) - result.getLineLeft(last)).toInt()
        val needed = lastLine + META_GAP.roundToPx() + time.width
        val inline = needed <= constraints.maxWidth
        val width = (if (inline) maxOf(words.width, needed) else maxOf(words.width, time.width))
            .coerceIn(constraints.minWidth, constraints.maxWidth)
        // Inline, the time sits a little under the last line's baseline (H4).
        val height = if (inline) maxOf(words.height + drop, time.height) else words.height + time.height
        return layout(width, height) {
            words.placeRelative(0, 0)
            time.placeRelative(width - time.width, height - time.height)
        }
    }

    override fun IntrinsicMeasureScope.maxIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int {
        val words = measurables[0].maxIntrinsicWidth(height)
        val time = measurables.getOrNull(1)?.maxIntrinsicWidth(height) ?: 0
        return if (time == 0) words else words + META_GAP.roundToPx() + time
    }

    override fun IntrinsicMeasureScope.minIntrinsicWidth(measurables: List<IntrinsicMeasurable>, height: Int): Int =
        maxOf(measurables[0].minIntrinsicWidth(height), measurables.getOrNull(1)?.minIntrinsicWidth(height) ?: 0)

    override fun IntrinsicMeasureScope.minIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int =
        height(measurables, width)

    override fun IntrinsicMeasureScope.maxIntrinsicHeight(measurables: List<IntrinsicMeasurable>, width: Int): Int =
        height(measurables, width)

    // The time under the text: the most it can take, wherever the time ends up.
    private fun IntrinsicMeasureScope.height(measurables: List<IntrinsicMeasurable>, width: Int): Int =
        measurables[0].maxIntrinsicHeight(width) +
            maxOf(META_DROP.roundToPx(), measurables.getOrNull(1)?.maxIntrinsicHeight(Constraints.Infinity) ?: 0)
}

private val META_GAP = 6.dp

/** H4: the time and the mark stand 6 over the bubble's bottom edge, [META_DROP] under the text's last line. */
private val META_BOTTOM = 6.dp
private val META_DROP = 3.dp
private const val META_OPACITY = 0.65f
private const val META_MAX_SIZE = 13f

/** Centred grey text with small avatars: "Leyla söhbətə qoşuldu". */
@Composable
private fun SystemLineView(line: SystemLine, theme: ClomniTheme) {
    Row(
        Modifier.fillMaxWidth().padding(top = ClomniTheme.Space.m.dp, bottom = ClomniTheme.Space.xs.dp),
        horizontalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xs.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (line.avatars.isNotEmpty()) {
            val ring = 2.dp
            Row(
                Modifier.bleed(ring, ring).clearAndSetSemantics {},
                horizontalArrangement = Arrangement.spacedBy(-ClomniTheme.Size.headerAvatarOverlap.dp - ring * 2),
            ) {
                for (avatar in line.avatars) {
                    Box(Modifier.clip(CircleShape).background(theme.colors.background.color).padding(ring)) {
                        ChatAvatarView(avatar, ClomniTheme.Size.headerAvatar, theme)
                    }
                }
            }
        }
        BasicText(
            line.text,
            Modifier.weight(1f, fill = false),
            style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary).copy(textAlign = TextAlign.Center),
        )
    }
}

/** Three dots in a bot bubble; they pulse unless animations are off. */
@Composable
private fun TypingRow(line: TypingLine, theme: ClomniTheme) {
    val still = reduceMotion() || LocalInspectionMode.current
    // M4: one wave through the three dots, 1.2 s round, each 0.15 s behind the one before; still, they rest.
    val phase = if (still) {
        null
    } else {
        rememberInfiniteTransition(label = "typing").animateFloat(
            0f,
            1f,
            infiniteRepeatable(tween(TYPING_PERIOD_MS, easing = LinearEasing), RepeatMode.Restart),
            label = "dots",
        )
    }
    Row(
        Modifier.padding(top = 4.dp).clearAndSetSemantics { contentDescription = line.accessibilityLabel },
        verticalAlignment = Alignment.Bottom,
    ) {
        ChatAvatarView(line.avatar, ClomniTheme.Size.avatar, theme)
        Spacer(Modifier.width(ClomniTheme.Space.s.dp))
        Row(
            Modifier.clip(RoundedCornerShape(ClomniTheme.Radius.message.dp))
                .background(theme.colors.surface.color)
                .padding(vertical = 12.dp, horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            val lift = with(LocalDensity.current) { 2.dp.toPx() }
            for (index in 0 until 3) {
                Box(
                    Modifier.size(6.dp).graphicsLayer {
                        val t = phase?.value
                        if (t == null) {
                            alpha = 0.5f + 0.2f * index
                        } else {
                            val wave = (sin(2 * PI * (t - index * TYPING_LAG_MS / TYPING_PERIOD_MS.toFloat())).toFloat() + 1f) / 2f
                            alpha = 0.4f + 0.5f * wave
                            translationY = -lift * wave
                        }
                    }.clip(CircleShape).background(theme.colors.textSecondary.color),
                )
            }
        }
    }
}

private const val TYPING_PERIOD_MS = 1_200
private const val TYPING_LAG_MS = 150

/** A person's face, or the bot's: a brand-coloured circle with its initial until its picture is here. */
@Composable
internal fun ChatAvatarView(avatar: ChatAvatar, size: Float, theme: ClomniTheme) {
    if (!avatar.isBot) {
        Avatar(avatar.url, avatar.initial, size, theme, Modifier.clearAndSetSemantics {})
        return
    }
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(theme.colors.primary.color).clearAndSetSemantics {},
        Alignment.Center,
    ) {
        val fontSize: TextUnit = with(LocalDensity.current) { (size * 0.45f).dp.toSp() }
        BasicText(
            avatar.initial,
            style = clomniText(0f, theme.colors.onPrimary, FontWeight.Bold).copy(fontSize = fontSize, lineHeight = fontSize),
        )
        avatar.url?.let { RemoteImageFill(it, ImageSizing.Kind.ICON, size, Color.Transparent) }
    }
}
