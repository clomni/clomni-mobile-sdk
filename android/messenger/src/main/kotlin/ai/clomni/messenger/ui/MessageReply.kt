package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.DeleteConfirm
import ai.clomni.messenger.presentation.RgbColor
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

/** What a bubble needs from its transcript besides its own data: the menu's words, and where a quote leads. */
internal class TranscriptLinks(
    val replyLabel: String = "",
    val copyLabel: String = "",
    /** «Sil» and its question (SDK 1.0.7). */
    val deleteLabel: String = "",
    val deleteConfirm: DeleteConfirm = DeleteConfirm(),
    /** The bubble a quote has just led to, lit for a second. */
    val highlighted: String? = null,
    /** A tap on a quote: scroll to the quoted message. */
    val jump: (messageId: String) -> Unit = {},
)

internal val LocalTranscript = compositionLocalOf { TranscriptLinks() }

/** Who wrote the quoted message (semibold) over one or two lines of it, as one text. */
private fun quoteText(quote: Bubble.Quote, excerptColor: Color): AnnotatedString = buildAnnotatedString {
    if (quote.author.isNotEmpty()) {
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(quote.author) }
        append('\n')
    }
    withStyle(SpanStyle(color = excerptColor)) { append(quote.excerpt) }
}

/**
 * Inside the bubble, at its top: who wrote the quoted message and two lines of it, on the text colour at 6% (radius
 * 10). On the user's brand-coloured bubble the "text" is the colour on it, so its tint is a little stronger there.
 */
@Composable
internal fun QuoteBlock(quote: Bubble.Quote, ink: RgbColor, outgoing: Boolean, modifier: Modifier = Modifier) {
    val jump = LocalTranscript.current.jump
    BasicText(
        quoteText(quote, ink.color.copy(alpha = if (outgoing) 0.85f else 0.7f)),
        modifier.widthIn(min = 48.dp).heightIn(min = 48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(ink.color.copy(alpha = if (outgoing) 0.16f else 0.06f))
            .clickable(role = Role.Button) { jump(quote.messageId) }
            .clearAndSetSemantics {
                contentDescription = "${quote.author}: ${quote.excerpt}"
                role = Role.Button
            }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        style = clomniText(13f, ink),
        maxLines = if (quote.author.isEmpty()) 2 else 3,
        overflow = TextOverflow.Ellipsis,
    )
}

/** Over the field while answering: the brand's 3 dp line, who wrote it (13 semibold), one line of it, and ✕. */
@Composable
internal fun QuoteStrip(quote: Bubble.Quote, cancelLabel: String, theme: ClomniTheme, cancel: () -> Unit) {
    Row(Modifier.padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        val line = theme.colors.primary.color
        BasicText(
            quoteText(quote, theme.colors.textSecondary.color),
            Modifier.weight(1f)
                .drawBehind { drawRect(line, size = Size(3.dp.toPx(), size.height)) }
                .padding(start = 13.dp)
                .clearAndSetSemantics { contentDescription = "${quote.author}: ${quote.excerpt}" },
            style = clomniText(13f, theme.colors.textPrimary),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Box(Modifier.size(48.dp).button(cancelLabel, CircleShape, 32.dp, cancel), Alignment.Center) {
            Icon(R.drawable.clomni_ic_close, theme.colors.textSecondary, 18.dp)
        }
    }
}

/**
 * A bubble being dragged to the right to answer it: [offset] follows the finger while [dragging], then springs back
 * ([shown]). Letting go past [THRESHOLD_DP] answers.
 */
internal class ReplySwipe {
    var offset by mutableFloatStateOf(0f)
    var dragging by mutableStateOf(false)

    /** What is drawn: the finger's offset, or on its way back. */
    lateinit var shown: State<Float>
}

/**
 * A drag to the right answers the message: the bubble follows the finger (with some resistance), the reply arrow comes
 * in behind it, a light tick at the threshold, and it springs back. Vertical drags stay the list's.
 */
@Composable
internal fun Modifier.swipeToReply(enabled: Boolean, swipe: ReplySwipe, reply: () -> Unit): Modifier {
    swipe.shown = animateFloatAsState(
        if (swipe.dragging) swipe.offset else 0f,
        if (swipe.dragging) snap() else spring(dampingRatio = 0.7f, stiffness = 500f),
        label = "swipe",
    )
    if (!enabled) return this
    val haptic = LocalHapticFeedback.current
    val onReply by rememberUpdatedState(reply)
    val threshold = with(LocalDensity.current) { THRESHOLD_DP.dp.toPx() }
    return pointerInput(swipe) {
        detectHorizontalDragGestures(
            onDragStart = { swipe.dragging = true },
            onDragEnd = {
                if (swipe.offset >= threshold) onReply()
                swipe.dragging = false
                swipe.offset = 0f
            },
            onDragCancel = {
                swipe.dragging = false
                swipe.offset = 0f
            },
        ) { change, amount ->
            val before = swipe.offset
            swipe.offset = (before + amount * 0.7f).coerceIn(0f, threshold + 24.dp.toPx())
            if (swipe.offset != before) change.consume()
            if (before < threshold && swipe.offset >= threshold) haptic.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
        }
    }.graphicsLayer { translationX = swipe.shown.value }
}

/** The reply arrow behind a swiped bubble: it fades and grows in as the drag nears the threshold. */
@Composable
internal fun ReplyArrow(swipe: ReplySwipe, theme: ClomniTheme, modifier: Modifier = Modifier) {
    val threshold = with(LocalDensity.current) { THRESHOLD_DP.dp.toPx() }
    Icon(
        R.drawable.clomni_ic_reply,
        theme.colors.textSecondary,
        16.dp,
        modifier.graphicsLayer {
            val progress = (swipe.shown.value / threshold).coerceIn(0f, 1f)
            alpha = progress
            scaleX = 0.6f + 0.4f * progress
            scaleY = scaleX
        }.size(28.dp).clip(CircleShape).background(theme.colors.surface.color).padding(6.dp),
    )
}

/**
 * A long press: "Cavabla" (while there is a composer), "Kopyala" (when there is text) and, on the user's own message
 * while the conversation is open, «Sil» in the error colour, which asks first ([delete] opens the question); over the
 * bubble.
 */
@Composable
internal fun MessageMenu(bubble: Bubble, theme: ClomniTheme, reply: (String) -> Unit, delete: () -> Unit, dismiss: () -> Unit) {
    val gap = with(LocalDensity.current) { 6.dp.roundToPx() }
    Popup(
        popupPositionProvider = AboveOrBelow(gap, bubble.side == Bubble.Side.OUTGOING),
        onDismissRequest = dismiss,
        properties = PopupProperties(focusable = true),
    ) {
        MessageMenuContent(bubble, theme, reply, delete, dismiss)
    }
}

/** The menu's card, apart from its popup so a screenshot can draw it. */
@Composable
internal fun MessageMenuContent(bubble: Bubble, theme: ClomniTheme, reply: (String) -> Unit, delete: () -> Unit, dismiss: () -> Unit) {
    val links = LocalTranscript.current
    val context = LocalContext.current
    val shape = RoundedCornerShape(ClomniTheme.Radius.card.dp)
    Column(
        Modifier.padding(8.dp).shadow(8.dp, shape, ambientColor = Color.Black.copy(alpha = 0.06f), spotColor = Color.Black.copy(alpha = 0.12f))
            .clip(shape).background(theme.colors.background.color),
    ) {
        val messageId = bubble.messageId
        if (bubble.replyable && messageId != null) {
            MenuRow(links.replyLabel, theme) {
                dismiss()
                reply(messageId)
            }
        }
        bubble.copyText?.let { text ->
            MenuRow(links.copyLabel, theme) {
                dismiss()
                copyText(context, text)
            }
        }
        if (bubble.deletable) {
            MenuRow(links.deleteLabel, theme, theme.colors.errorText) {
                dismiss()
                delete()
            }
        }
    }
}

@Composable
private fun MenuRow(label: String, theme: ClomniTheme, ink: RgbColor = theme.colors.textPrimary, onClick: () -> Unit) {
    BasicText(
        label,
        Modifier.widthIn(min = 160.dp).heightIn(min = 48.dp).button(label, onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp),
        style = clomniText(ClomniTheme.FontSize.text, ink),
    )
}

/** Whether a bubble has a menu at all. */
internal val Bubble.hasMenu: Boolean get() = (replyable && messageId != null) || copyText != null || deletable

/**
 * "Mesaj silinsin?" before the user's message goes for everyone: the title, the line under it, then «Ləğv et» and «Sil»
 * (the error colour) at the end, as the platform's dialogs are. [delete] runs once confirmed; either button closes it.
 */
@Composable
internal fun DeleteDialog(texts: DeleteConfirm, theme: ClomniTheme, delete: () -> Unit, dismiss: () -> Unit) {
    Dialog(dismiss) { DeleteDialogContent(texts, theme, delete, dismiss) }
}

/** The dialog's card, apart from its window so a screenshot can draw it: 24 inside, radius 28, as Material 3's. */
@Composable
internal fun DeleteDialogContent(texts: DeleteConfirm, theme: ClomniTheme, delete: () -> Unit, dismiss: () -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    Column(
        Modifier.widthIn(min = 280.dp, max = 560.dp).clip(shape)
            .background((if (theme.isDark) theme.colors.surface else theme.colors.background).color)
            .padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 16.dp),
    ) {
        BasicText(
            texts.title,
            Modifier.semantics { heading() },
            style = clomniText(20f, theme.colors.textPrimary, FontWeight.SemiBold, lineHeight = 1.3f),
        )
        BasicText(
            texts.body,
            Modifier.padding(top = 12.dp),
            style = clomniText(ClomniTheme.FontSize.text, theme.colors.textSecondary, lineHeight = 1.45f),
        )
        Row(Modifier.align(Alignment.End).padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DialogButton(texts.cancel, theme.colors.primaryText, dismiss)
            DialogButton(texts.delete, theme.colors.errorText) {
                dismiss()
                delete()
            }
        }
    }
}

@Composable
private fun DialogButton(label: String, ink: RgbColor, onClick: () -> Unit) {
    BasicText(
        label,
        Modifier.heightIn(min = 48.dp).widthIn(min = 48.dp).button(label, RoundedCornerShape(20.dp), onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        style = clomniText(ClomniTheme.FontSize.text, ink, FontWeight.Medium),
    )
}

internal fun copyText(context: Context, text: String) {
    runCatching { context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(null, text)) }
}

/** Over the bubble when there is room, under it otherwise; along its own side of the screen. */
private class AboveOrBelow(private val gap: Int, private val alignEnd: Boolean) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val x = if (alignEnd) anchorBounds.right - popupContentSize.width else anchorBounds.left
        val above = anchorBounds.top - gap - popupContentSize.height
        val y = if (above >= 0) above else (anchorBounds.bottom + gap).coerceAtMost((windowSize.height - popupContentSize.height).coerceAtLeast(0))
        return IntOffset(x.coerceIn(0, (windowSize.width - popupContentSize.width).coerceAtLeast(0)), y)
    }
}

/** How far a bubble is dragged before letting go answers it. */
private const val THRESHOLD_DP = 56
