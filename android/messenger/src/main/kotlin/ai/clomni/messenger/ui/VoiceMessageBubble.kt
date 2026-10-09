package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.VoiceNote
import ai.clomni.messenger.presentation.VoicePlayer
import ai.clomni.messenger.presentation.Waveform
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** [VoicePlayer] for Compose: [version] moves with every change, so a bubble reading it redraws. */
internal class VoicePlayback(val player: VoicePlayer) {
    var version by mutableIntStateOf(0)
        private set

    init {
        player.onChange = { version++ }
    }

    /** Read in a composable: it redraws when the track changes. */
    fun track(id: String): VoicePlayer.Track = version.let { player.track(id) }

    val speed: VoicePlayer.Speed get() = version.let { player.speed }
}

/** One player for the conversation's screen, let go with it. */
@Composable
internal fun rememberVoicePlayback(): VoicePlayback {
    val context = LocalContext.current.applicationContext
    val playback = remember { VoicePlayback(VoicePlayer(VoiceAudio.files(context), MediaPlayerOutput(context), VoiceAudio.scheduler)) }
    DisposableEffect(playback) { onDispose { playback.player.release() } }
    return playback
}

/**
 * A voice message in its bubble, as WhatsApp draws one: the round play button (a ring turns in it while the file comes
 * or the user's recording uploads), the waveform filling as it plays (tap or drag it to move), under it the length, or
 * what is left while it plays, and the bubble's time and ✓✓ ([meta]) at its bottom end; while it plays, the speed
 * (1× → 1.5× → 2×). Only the content: the caller gives the bubble's shape and colour.
 */
@Composable
internal fun VoiceMessageBubble(
    note: VoiceNote,
    playback: VoicePlayback,
    theme: ClomniTheme,
    strings: ClomniStrings,
    meta: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    val player = playback.player
    // A length the message does not say comes from the file: fetched once, before the first play.
    val remote = note.source as? VoicePlayer.Source.Remote
    if (note.durationMs == null && remote != null && !LocalInspectionMode.current) {
        LaunchedEffect(note.id) { player.prefetch(note.id, remote.url) }
    }
    VoiceMessageContent(
        note, playback.track(note.id), playback.speed, theme, strings,
        toggle = { player.toggle(note.id, note.source, note.durationMs) },
        seek = { player.seek(note.id, it, note.durationMs) },
        cycleSpeed = player::cycleSpeed,
        meta = meta,
        modifier = modifier,
    )
}

/** [VoiceMessageBubble] for a given [track] and [speed]: what the screenshots draw. */
@Composable
internal fun VoiceMessageContent(
    note: VoiceNote,
    track: VoicePlayer.Track,
    speed: VoicePlayer.Speed,
    theme: ClomniTheme,
    strings: ClomniStrings,
    toggle: () -> Unit,
    seek: (Float) -> Unit,
    cycleSpeed: () -> Unit,
    meta: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = theme.colors
    val fill = if (note.outgoing) colors.primary else colors.surface
    val ink = if (note.outgoing) colors.onPrimary else colors.textPrimary
    val played = if (note.outgoing) colors.onPrimary else colors.primaryText
    val unplayed = (if (note.outgoing) colors.onPrimary else colors.textSecondary).color.copy(alpha = 0.42f)
    val phase = track.phase
    val started = phase == VoicePlayer.Phase.PLAYING || (phase == VoicePlayer.Phase.PAUSED && track.positionMs > 0)
    Column(modifier.widthIn(min = 220.dp, max = 260.dp).padding(start = 8.dp, end = 12.dp, top = 8.dp, bottom = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // The circle: the brand's on the operator's bubble, on_primary on the user's; the icon in the other colour.
            val circle = if (note.outgoing) colors.onPrimary else colors.primary
            val glyph = if (note.outgoing) colors.primary else colors.onPrimary
            val playing = phase == VoicePlayer.Phase.PLAYING
            Box(
                Modifier.bleed(4.dp, 4.dp).size(48.dp).button(strings[if (playing) Key.VOICE_PAUSE else Key.VOICE_PLAY], CircleShape, 40.dp, toggle)
                    .padding(4.dp).background(circle.color, CircleShape),
                Alignment.Center,
            ) {
                if (phase == VoicePlayer.Phase.LOADING || note.sending) Spinner(glyph, strings[Key.LOADING], size = 34.dp)
                // The triangle's weight sits left of its box: a point to the right centres it.
                Icon(if (playing) R.drawable.clomni_ic_pause else R.drawable.clomni_ic_play, glyph, 20.dp, Modifier.padding(start = if (playing) 0.dp else 1.dp))
            }
            WaveformBar(
                note.waveform, track.progress, played.color, unplayed, started,
                note.accessibilityLabel(track, strings), note.time(track), seek,
                Modifier.padding(start = 8.dp).weight(1f).height(32.dp),
            )
            if (started) {
                BasicText(
                    speed.label,
                    Modifier.padding(start = 6.dp).bleed(8.dp, 12.dp).sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                        .button("${strings[Key.VOICE_SPEED]} ${speed.label}", RoundedCornerShape(12.dp), onClick = cycleSpeed)
                        .wrapContentSize().background(ink.over(fill, 0.16).color, RoundedCornerShape(12.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
                    style = clomniText(ClomniTheme.FontSize.label, ink, FontWeight.SemiBold, lineHeight = 1.2f),
                )
            }
        }
        Row(Modifier.fillMaxWidth().padding(start = 48.dp), verticalAlignment = Alignment.Bottom) {
            val failed = phase == VoicePlayer.Phase.FAILED
            BasicText(
                if (failed) strings[Key.VOICE_UNAVAILABLE] else note.time(track),
                Modifier.weight(1f).clearAndSetSemantics {},
                style = clomniText(ClomniTheme.FontSize.label, if (failed) ink else ink.over(fill, 0.75), lineHeight = 1.2f)
                    .copy(fontFeatureSettings = "tnum"),
                maxLines = 1,
            )
            meta()
        }
    }
}

/**
 * [waveform]'s bars (2.5 dp, 2 apart, rounded), those already heard in [played], and with [playhead] the dot where it
 * is. A tap or a drag moves it there ([seek]); TalkBack reads [label] and [state] and moves it as a slider. Shared by
 * the bubble and the recorder's preview.
 */
@Composable
internal fun WaveformBar(
    waveform: List<Int>?,
    progress: Float,
    played: Color,
    unplayed: Color,
    playhead: Boolean,
    label: String,
    state: String,
    seek: (Float) -> Unit,
    modifier: Modifier,
) {
    var dragged by remember { mutableStateOf<Float?>(null) }
    Canvas(
        modifier
            .pointerInput(seek) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    val width = size.width.coerceAtLeast(1).toFloat()
                    var at = down.position.x
                    do {
                        dragged = (at / width).coerceIn(0f, 1f)
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                        change?.consume()
                        at = change?.position?.x ?: at
                    } while (change?.pressed == true)
                    dragged?.let(seek)
                    dragged = null
                }
            }
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = state
                progressBarRangeInfo = ProgressBarRangeInfo(progress, 0f..1f)
                setProgress {
                    seek(it)
                    true
                }
            },
    ) {
        val shown = dragged ?: progress
        drawBars(Waveform.bars(waveform, barCount()), shown, played, unplayed)
        if (playhead || dragged != null) drawCircle(played, 5.dp.toPx(), Offset((size.width - GAP.toPx()) * shown, size.height / 2))
    }
}

private val BAR = 2.5.dp
private val GAP = 2.dp

/** How many bars fit the drawing's width. */
internal fun DrawScope.barCount(): Int = ((size.width + GAP.toPx()) / (BAR + GAP).toPx()).toInt().coerceAtLeast(1)

/** Bars of [heights] (0–1 of the height), centred; those before [progress] in [played]. */
internal fun DrawScope.drawBars(heights: List<Float>, progress: Float, played: Color, unplayed: Color) {
    val bar = BAR.toPx()
    val step = bar + GAP.toPx()
    val middle = size.height / 2
    heights.forEachIndexed { index, height ->
        val half = (size.height * height).coerceAtLeast(bar) / 2 - bar / 2
        val x = index * step + bar / 2
        val color = if ((index + 0.5f) / heights.size <= progress) played else unplayed
        drawLine(color, Offset(x, middle - half), Offset(x, middle + half), bar, StrokeCap.Round)
    }
}
