package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ChatAvatar
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Media
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.SystemLine
import ai.clomni.messenger.presentation.TextRun
import ai.clomni.messenger.presentation.TypingLine
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
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
    val pickFile: () -> Unit = {},
    val startNew: () -> Unit = {},
    val tap: (buttonId: String, messageId: String) -> Unit = { _, _ -> },
    /** The errors to show by field; empty when the form went. */
    val submit: (messageId: String, values: Map<String, String>) -> Map<String, String> = { _, _ -> emptyMap() },
    val retry: (clientId: String) -> Unit = {},
    /** "Yenidən cəhd et" after a failed first load. */
    val retryLoad: () -> Unit = {},
    val openImage: (url: String) -> Unit = {},
    val reachedTop: () -> Unit = {},
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
    return remember(context) {
        runCatching {
            android.provider.Settings.Global.getFloat(
                context.contentResolver,
                android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        }.getOrDefault(false)
    }
}

/** A new item comes in 6 dp from below while it fades in (220 ms, ease-out); with less motion it only fades. */
@Composable
internal fun Modifier.appearing(animate: Boolean, reduceMotion: Boolean): Modifier {
    if (!animate) return this
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) { progress.animateTo(1f, tween(220, easing = FastOutSlowInEasing)) }
    val rise = with(LocalDensity.current) { 6.dp.toPx() }
    return graphicsLayer {
        alpha = progress.value
        if (!reduceMotion) translationY = (1f - progress.value) * rise
    }
}

@Composable
internal fun ChatItemView(item: ChatItem, theme: ClomniTheme, actions: ChatActions) {
    when (item) {
        is ChatItem.TimeItem -> BasicText(
            item.text,
            Modifier.fillMaxWidth().padding(top = 2.dp, bottom = ClomniTheme.Space.m.dp),
            style = clomniText(11.5f, theme.colors.textSecondary).copy(textAlign = TextAlign.Center),
        )
        is ChatItem.BubbleItem -> BubbleRow(item.bubble, theme, actions)
        is ChatItem.SystemItem -> SystemLineView(item.line, theme)
        is ChatItem.RepliesItem -> QuickRepliesView(item.block, theme) { buttonId -> actions.tap(buttonId, item.block.messageId) }
        is ChatItem.TypingItem -> TypingRow(item.line, theme)
    }
}

/** 16 dp, 5 where bubbles of one run meet; the user's always keep the 5 dp bottom-end corner. */
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

/** A bubble with its avatar slot, meta line and status, on its side of the screen. */
@Composable
internal fun BubbleRow(bubble: Bubble, theme: ClomniTheme, actions: ChatActions) {
    val incoming = bubble.side == Bubble.Side.INCOMING
    val startsRun = bubble.position == Bubble.Position.FIRST || bubble.position == Bubble.Position.SINGLE
    // A new run starts a little apart: 4 dp for the other side, 8 dp for the user.
    val top = if (startsRun) (if (incoming) 4.dp else 8.dp) else 0.dp
    Column(
        Modifier.fillMaxWidth().padding(top = top),
        horizontalAlignment = if (incoming) Alignment.Start else Alignment.End,
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            if (incoming) {
                val avatar = bubble.avatar
                if (avatar != null) {
                    ChatAvatarView(avatar, ClomniTheme.Size.headerAvatar, theme)
                } else {
                    Spacer(Modifier.width(ClomniTheme.Size.headerAvatar.dp))
                }
                Spacer(Modifier.width(ClomniTheme.Space.s.dp))
            } else {
                Spacer(Modifier.width(40.dp))
            }
            Box(Modifier.weight(1f, fill = false)) { BubbleBody(bubble, theme, actions) }
            if (incoming) Spacer(Modifier.width(40.dp))
        }
        bubble.meta?.let { meta ->
            BasicText(
                meta,
                Modifier.padding(top = 5.dp, start = 34.dp).clearAndSetSemantics {},
                style = clomniText(ClomniTheme.FontSize.meta, theme.colors.textSecondary),
            )
        }
        bubble.status?.let { StatusLine(it, theme, actions.retry) }
    }
}

/** The bubble itself: text, image, file card or form. */
@Composable
private fun BubbleBody(bubble: Bubble, theme: ClomniTheme, actions: ChatActions) {
    val incoming = bubble.side == Bubble.Side.INCOMING
    val fill = if (incoming) theme.colors.surface else theme.colors.primary
    val ink = if (incoming) theme.colors.textPrimary else theme.colors.onPrimary
    val shape = bubble.shape()
    when (val body = bubble.body) {
        is Bubble.TextBody -> BasicText(
            attributedText(body.runs, if (incoming) theme.colors.primary else theme.colors.onPrimary),
            Modifier.widthIn(max = if (incoming) 222.dp else 210.dp)
                .clip(shape)
                .background(fill.color)
                .padding(vertical = 9.dp, horizontal = ClomniTheme.Space.l.dp)
                .clearAndSetSemantics { contentDescription = bubble.accessibilityLabel },
            style = clomniText(ClomniTheme.FontSize.text, ink),
        )
        is Bubble.ImageBody -> ImageBubble(body, bubble.accessibilityLabel, theme, fill, ink, actions.openImage)
        is Bubble.FileBody -> {
            val uriHandler = LocalUriHandler.current
            FileCard(
                body,
                ink,
                Modifier.clip(shape).background(fill.color)
                    .clickable(enabled = body.url != null, role = Role.Button) {
                        body.url?.let { runCatching { uriHandler.openUri(it) } }
                    }
                    .clearAndSetSemantics {
                        contentDescription = bubble.accessibilityLabel
                        role = Role.Button
                    },
            )
        }
        is ai.clomni.messenger.presentation.FormCard -> FormCardView(
            body,
            theme,
            Modifier.widthIn(max = 260.dp).clip(shape).background(fill.color),
        ) { values -> actions.submit(body.messageId, values) }
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
) {
    val shape = RoundedCornerShape(ClomniTheme.Radius.card.dp)
    val model: Any? = if (LocalInspectionMode.current) null else image.localFile ?: image.url
    val painter = rememberAsyncImagePainter(model)
    val loaded = (painter.state as? AsyncImagePainter.State.Success)?.painter?.intrinsicSize
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
            .clickable(enabled = target != null, role = Role.Button) { target?.let(open) }
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Image
            },
    ) {
        Box(Modifier.size(width.dp, height.dp).background(theme.colors.surface.color)) {
            if (model != null) {
                Image(painter, null, Modifier.size(width.dp, height.dp), contentScale = ContentScale.Crop)
            }
        }
        image.caption?.let { caption ->
            BasicText(
                attributedText(caption, ink),
                Modifier.width(width.dp).background(fill.color).padding(vertical = 9.dp, horizontal = ClomniTheme.Space.l.dp),
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
    val style = clomniText(ClomniTheme.FontSize.meta, if (status.isFailure) theme.colors.unread else theme.colors.textSecondary)
    val retryId = status.retryId
    if (retryId == null) {
        BasicText(status.text, Modifier.padding(top = 5.dp), style = style)
    } else {
        // The 15 dp line reaches a 48 dp target without moving anything.
        val reach = 16.dp
        BasicText(
            status.text,
            Modifier.padding(top = 5.dp).bleed(vertical = reach).button(status.text) { retry(retryId) }.padding(vertical = reach),
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
                Modifier.clearAndSetSemantics {},
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
        ChatAvatarView(line.avatar, ClomniTheme.Size.headerAvatar, theme)
        Spacer(Modifier.width(ClomniTheme.Space.s.dp))
        Row(
            Modifier.clip(RoundedCornerShape(ClomniTheme.Radius.message.dp))
                .background(theme.colors.surface.color)
                .padding(vertical = 12.dp, horizontal = 13.dp),
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
        val url = avatar.url
        if (url != null && !LocalInspectionMode.current) {
            coil.compose.AsyncImage(url, null, Modifier.size(size.dp), contentScale = ContentScale.Crop)
        }
    }
}
