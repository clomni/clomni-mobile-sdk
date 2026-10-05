package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.Bubble
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.RgbColor
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.launch

/** What a bubble needs from its transcript besides its own data: the menu's words, and where a quote leads. */
internal class TranscriptLinks(
    val replyLabel: String = "",
    val copyLabel: String = "",
    /** The bubble a quote has just led to, lit for a second. */
    val highlighted: String? = null,
    /** A tap on a quote: scroll to the quoted message. */
    val jump: (messageId: String) -> Unit = {},
)

internal val LocalTranscript = compositionLocalOf { TranscriptLinks() }

/**
 * Inside the bubble, at its top: who wrote the quoted message and two lines of it, on the text colour at 6% (radius
 * 10). On the user's brand-coloured bubble the "text" is the white on it, so its tint is a little stronger there.
 */
@Composable
internal fun QuoteBlock(quote: Bubble.Quote, ink: RgbColor, outgoing: Boolean, modifier: Modifier = Modifier) {
    val jump = LocalTranscript.current.jump
    val label = listOf(quote.author, quote.excerpt).filter { it.isNotEmpty() }.joinToString(": ")
    Column(
        modifier.widthIn(min = 48.dp).heightIn(min = 48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(ink.color.copy(alpha = if (outgoing) 0.16f else 0.06f))
            .clickable(role = Role.Button) { jump(quote.messageId) }
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
            }
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        if (quote.author.isNotEmpty()) {
            BasicText(quote.author, style = clomniText(13f, ink, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        BasicText(
            quote.excerpt,
            style = clomniText(13f, ink).copy(color = ink.color.copy(alpha = if (outgoing) 0.85f else 0.7f)),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Over the field while answering: the brand's 3 dp line, who wrote it (13 semibold), one line of it, and ✕. */
@Composable
internal fun QuoteStrip(quote: Bubble.Quote, cancelLabel: String, theme: ClomniTheme, cancel: () -> Unit) {
    Row(Modifier.padding(bottom = 8.dp).height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(theme.colors.primary.color))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f).clearAndSetSemantics { contentDescription = "${quote.author}: ${quote.excerpt}" }) {
            BasicText(
                quote.author,
                style = clomniText(13f, theme.colors.textPrimary, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            BasicText(quote.excerpt, style = clomniText(13f, theme.colors.textSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(48.dp).button(cancelLabel, CircleShape, 32.dp, cancel), Alignment.Center) {
            Icon(R.drawable.clomni_ic_close, theme.colors.textSecondary, 18.dp)
        }
    }
}

/**
 * A drag to the right answers the message: the bubble follows the finger (with some resistance), the reply arrow
 * comes in behind it, a light tick at [THRESHOLD_DP], and it springs back. Vertical drags stay the list's.
 */
@Composable
internal fun Modifier.swipeToReply(enabled: Boolean, key: Any, reply: () -> Unit, drawn: (Float) -> Unit): Modifier {
    if (!enabled) return this
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    val threshold = with(density) { THRESHOLD_DP.dp.toPx() }
    val limit = with(density) { (THRESHOLD_DP + 24).dp.toPx() }
    val offset = remember(key) { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val onReply by rememberUpdatedState(reply)
    val report by rememberUpdatedState(drawn)
    LaunchedEffect(offset) {
        snapshotFlow { offset.value }.collect { report((it / threshold).coerceIn(0f, 1f)) }
    }
    val back = spring<Float>(dampingRatio = 0.7f, stiffness = 500f)
    return pointerInput(key) {
        var armed = false
        detectHorizontalDragGestures(
            onDragStart = { armed = false },
            onDragEnd = {
                if (armed) onReply()
                scope.launch { offset.animateTo(0f, back) }
            },
            onDragCancel = { scope.launch { offset.animateTo(0f, back) } },
        ) { change, amount ->
            val next = (offset.value + amount * 0.7f).coerceIn(0f, limit)
            if (next != offset.value) change.consume()
            scope.launch { offset.snapTo(next) }
            val past = next >= threshold
            if (past && !armed) haptic.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
            armed = past
        }
    }.graphicsLayer { translationX = offset.value }
}

/** The reply arrow behind a swiped bubble: it fades and grows in as the drag nears the threshold. */
@Composable
internal fun ReplyArrow(progress: Float, theme: ClomniTheme, modifier: Modifier = Modifier) {
    if (progress <= 0f) return
    Box(
        modifier.size(28.dp).graphicsLayer {
            alpha = progress
            scaleX = 0.6f + 0.4f * progress
            scaleY = 0.6f + 0.4f * progress
        }.clip(CircleShape).background(theme.colors.surface.color),
        Alignment.Center,
    ) {
        Icon(R.drawable.clomni_ic_reply, theme.colors.textSecondary, 16.dp)
    }
}

/** A long press: "Cavabla" (while there is a composer) and "Kopyala" (when there is text), over the bubble. */
@Composable
internal fun MessageMenu(bubble: Bubble, theme: ClomniTheme, reply: (String) -> Unit, dismiss: () -> Unit) {
    val links = LocalTranscript.current
    val context = LocalContext.current
    val outgoing = bubble.side == Bubble.Side.OUTGOING
    val gap = with(LocalDensity.current) { 6.dp.roundToPx() }
    val shown = remember { Animatable(0f) }
    val still = reduceMotion()
    LaunchedEffect(Unit) { if (still) shown.snapTo(1f) else shown.animateTo(1f, spring(dampingRatio = 0.86f, stiffness = 600f)) }
    Popup(popupPositionProvider = AboveOrBelow(gap, outgoing), onDismissRequest = dismiss, properties = PopupProperties(focusable = true)) {
        val shape = RoundedCornerShape(ClomniTheme.Radius.card.dp)
        Column(
            Modifier.graphicsLayer {
                alpha = shown.value
                val scale = 0.92f + 0.08f * shown.value
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(if (outgoing) 1f else 0f, 1f)
            }.padding(8.dp).shadow(8.dp, shape, ambientColor = Color.Black.copy(alpha = 0.06f), spotColor = Color.Black.copy(alpha = 0.12f))
                .clip(shape).background(theme.colors.background.color).width(IntrinsicSize.Max),
        ) {
            val messageId = bubble.messageId
            if (bubble.replyable && messageId != null) {
                MenuRow(links.replyLabel, R.drawable.clomni_ic_reply, theme) {
                    dismiss()
                    reply(messageId)
                }
            }
            bubble.copyText?.let { text ->
                MenuRow(links.copyLabel, R.drawable.clomni_ic_copy, theme) {
                    dismiss()
                    copyText(context, text)
                }
            }
        }
    }
}

@Composable
private fun MenuRow(label: String, icon: Int, theme: ClomniTheme, onClick: () -> Unit) {
    Row(
        Modifier.widthIn(min = 160.dp).heightIn(min = 48.dp).button(label, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, theme.colors.textSecondary, 20.dp)
        Spacer(Modifier.width(12.dp))
        BasicText(label, style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary))
    }
}

/** Whether a bubble has a menu at all. */
internal val Bubble.hasMenu: Boolean get() = (replyable && messageId != null) || copyText != null

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
internal const val THRESHOLD_DP = 56
