package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ChatAvatar
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.ImageSizing
import ai.clomni.messenger.presentation.Media
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.SystemLine
import ai.clomni.messenger.presentation.TextRun
import ai.clomni.messenger.presentation.TypingLine
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.unit.Dp
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.AnnotatedString
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
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter

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

/** The styled runs as one text: bold and italic spans; links underlined and tappable (https, tel, mailto only). */
@Composable
internal fun attributedText(runs: List<TextRun>, linkColor: RgbColor): AnnotatedString {
    val uriHandler = LocalUriHandler.current
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
                // An app that cannot open a tel: or mailto: link must not crash the conversation.
                withLink(LinkAnnotation.Url(link, styles) { runCatching { uriHandler.openUri(link) } }) {
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

/** A new item fades in (220 ms, ease-out), nothing moves (DESIGN-PASS 5: no flying elements). */
@Composable
internal fun Modifier.appearing(animate: Boolean): Modifier {
    if (!animate) return this
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) { progress.animateTo(1f, tween(220, easing = FastOutSlowInEasing)) }
    return graphicsLayer { alpha = progress.value }
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
 * A bubble with its avatar slot (28, next to the last of a run), the author over the first of a run (13 medium), the
 * time under the last (12), and the status, on its side of the screen. Bubbles of a run are 4 apart, runs 16. A bubble
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
    var pulled by remember { mutableFloatStateOf(0f) }
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
        if (incoming) ReplyArrow(pulled, theme, Modifier.align(Alignment.CenterStart))
        Column(
            Modifier.fillMaxWidth().swipeToReply(replyable, bubble.id, { messageId?.let(actions.reply) }) { pulled = it },
            horizontalAlignment = if (incoming) Alignment.Start else Alignment.End,
        ) {
            BubbleColumn(bubble, theme, actions, incoming, gutter, maxWidth, pulled, longPress, a11y)
            if (menu) MessageMenu(bubble, theme, actions.reply) { menu = false }
        }
    }
}

/** Who, the avatar slot, the bubble, then when and the status: the parts of a [BubbleRow] that move with a swipe. */
@Composable
private fun BubbleColumn(
    bubble: Bubble,
    theme: ClomniTheme,
    actions: ChatActions,
    incoming: Boolean,
    gutter: Dp,
    maxWidth: Dp,
    pulled: Float,
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
            if (!incoming) ReplyArrow(pulled, theme, Modifier.align(Alignment.CenterStart).offset(x = (-36).dp))
            BubbleBody(bubble, theme, actions, longPress, a11y)
        }
    }
    bubble.meta?.let { meta ->
        BasicText(
            meta,
            Modifier.padding(top = ClomniTheme.Space.xxs.dp, start = gutter).clearAndSetSemantics {},
            style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary),
        )
    }
    bubble.status?.let { StatusLine(it, theme, actions.retry) }
}

/** The bubble itself: text, image, file card or form; a quote at its top when it answers a message. */
@Composable
private fun BubbleBody(bubble: Bubble, theme: ClomniTheme, actions: ChatActions, longPress: (() -> Unit)?, a11y: List<CustomAccessibilityAction>) {
    val incoming = bubble.side == Bubble.Side.INCOMING
    val fill = if (incoming) theme.colors.surface else theme.colors.primary
    val ink = if (incoming) theme.colors.textPrimary else theme.colors.onPrimary
    val shape = bubble.shape()
    val quote = bubble.quote
    when (val body = bubble.body) {
        is Bubble.TextBody -> Column(
            Modifier.clip(shape)
                .background(fill.color)
                .then(if (longPress != null) Modifier.pointerInput(Unit) { detectTapGestures(onLongPress = { longPress() }) } else Modifier)
                .padding(vertical = if (quote != null) 6.dp else 10.dp, horizontal = if (quote != null) 6.dp else 14.dp),
        ) {
            if (quote != null) QuoteBlock(quote, ink, !incoming, Modifier.padding(bottom = 4.dp))
            BasicText(
                attributedText(body.runs, if (incoming) theme.colors.primaryText else theme.colors.onPrimary),
                (if (quote != null) Modifier.padding(start = 8.dp, end = 8.dp, bottom = 4.dp) else Modifier)
                    .clearAndSetSemantics {
                        contentDescription = bubble.accessibilityLabel
                        if (a11y.isNotEmpty()) customActions = a11y
                    },
                style = clomniText(ClomniTheme.FontSize.message, ink),
            )
        }
        is Bubble.ImageBody -> Quoted(quote, shape, fill, ink, !incoming) {
            ImageBubble(body, bubble.accessibilityLabel, theme, fill, ink, actions.openImage, longPress, a11y)
        }
        is Bubble.FileBody -> Quoted(quote, shape, fill, ink, !incoming) {
            val uriHandler = LocalUriHandler.current
            FileCard(
                body,
                ink,
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
    longPress: (() -> Unit)? = null,
    a11y: List<CustomAccessibilityAction> = emptyList(),
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
        }
        image.caption?.let { caption ->
            BasicText(
                attributedText(caption, ink),
                Modifier.width(width.dp).background(fill.color).padding(vertical = ClomniTheme.Space.s.dp, horizontal = ClomniTheme.Space.l.dp),
                style = clomniText(ClomniTheme.FontSize.text, ink),
            )
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

/** Icon, name (middle-truncated), size. */
@Composable
private fun FileCard(file: Bubble.FileBody, ink: RgbColor, modifier: Modifier) {
    Row(
        modifier.widthIn(max = 222.dp).padding(vertical = ClomniTheme.Space.m.dp, horizontal = ClomniTheme.Space.l.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
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
}

/** "Göndərildi", "Oxundu"; a failure in red, which sends again when tapped. */
@Composable
private fun StatusLine(status: Bubble.Status, theme: ClomniTheme, retry: (String) -> Unit) {
    val style = clomniText(ClomniTheme.FontSize.meta, if (status.isFailure) theme.colors.errorText else theme.colors.textSecondary)
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
    val pulse by if (still) {
        remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    } else {
        rememberInfiniteTransition(label = "typing").animateFloat(
            0f,
            1f,
            infiniteRepeatable(tween(600), RepeatMode.Reverse),
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
            for (index in 0 until 3) {
                val rest = 0.5f + 0.2f * index
                Box(
                    Modifier.size(6.dp).alpha(rest + (0.9f - rest) * pulse).clip(CircleShape)
                        .background(theme.colors.textSecondary.color),
                )
            }
        }
    }
}

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
