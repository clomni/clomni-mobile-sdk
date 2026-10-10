package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.VoiceClip
import ai.clomni.messenger.presentation.VoicePlayer
import ai.clomni.messenger.presentation.VoiceRecorderController
import ai.clomni.messenger.presentation.VoiceRecorderController.Hint
import ai.clomni.messenger.presentation.VoiceRecording
import ai.clomni.messenger.presentation.VoiceRecording.State
import ai.clomni.messenger.presentation.VoiceTime
import ai.clomni.messenger.presentation.Waveform
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import java.util.UUID

/** [VoiceRecorderController] for Compose: [version] moves with every change; [dropping] while the bin's animation runs. */
internal class VoiceRecorder(val controller: VoiceRecorderController, val maxSeconds: Int) {
    var version by mutableIntStateOf(0)
        private set

    /** A recording was thrown away: the microphone falls into the bin, the bar still there around it. */
    var dropping by mutableStateOf(false)

    private var discards = 0

    init {
        controller.onChange = {
            version++
            if (controller.discards != discards) {
                discards = controller.discards
                dropping = true
            }
        }
    }

    val state: State get() = version.let { controller.state }

    /** The bar takes the field's place: while recording, while listening back, and while the bin closes. */
    val showsBar: Boolean get() = state != State.Idle || dropping
}

/** The conversation's recorder, from [ClomniChat]; none without RECORD_AUDIO, in previews and screenshots. */
internal val LocalVoiceRecorder = staticCompositionLocalOf<VoiceRecorder?> { null }

/**
 * The conversation's recorder, or null when the app does not declare RECORD_AUDIO (no microphone then) or in a
 * preview. [send] gets each finished recording.
 */
@Composable
internal fun rememberVoiceRecorder(maxSeconds: Int, send: (VoiceClip) -> Unit): VoiceRecorder? {
    val context = LocalContext.current
    if (LocalInspectionMode.current || !remember { VoiceAudio.declared(context) }) return null
    val view = LocalView.current
    val sendLatest by rememberUpdatedState(send)
    val permission = rememberPermissionLauncher()
    val recorder = remember(maxSeconds) {
        val activity = context.activity()
        val haptics = mapOf(
            VoiceRecorderController.Feedback.START to HapticFeedbackConstants.VIRTUAL_KEY,
            VoiceRecorderController.Feedback.LOCK to HapticFeedbackConstants.CONTEXT_CLICK,
            VoiceRecorderController.Feedback.CANCEL to HapticFeedbackConstants.LONG_PRESS,
        )
        val controller = VoiceRecorderController(
            mic = MediaRecorderMic(context.applicationContext),
            permission = { VoiceAudio.permission(activity, context) },
            askPermission = {
                VoiceAudio.markAsked(context)
                permission?.launch(Manifest.permission.RECORD_AUDIO)
            },
            newFile = { VoiceAudio.newRecording(context) },
            scheduler = VoiceAudio.scheduler,
            now = SystemClock::elapsedRealtime,
            maxMs = maxSeconds * 1000L,
            send = { sendLatest(it) },
            feedback = { view.performHapticFeedback(haptics.getValue(it)) },
        )
        VoiceRecorder(controller, maxSeconds)
    }
    DisposableEffect(recorder) { onDispose { recorder.controller.close() } }
    return recorder
}

/** The system's microphone question, through the activity's result registry (as ChatView's pickers). */
@Composable
private fun rememberPermissionLauncher(): ActivityResultLauncher<String>? {
    val owner = LocalContext.current.registryOwner() ?: return null
    val key = rememberSaveable { UUID.randomUUID().toString() }
    val launcher = remember(owner, key) { owner.activityResultRegistry.register(key, ActivityResultContracts.RequestPermission()) {} }
    DisposableEffect(launcher) { onDispose { launcher.unregister() } }
    return launcher
}

private tailrec fun Context.registryOwner(): ActivityResultRegistryOwner? = when (this) {
    is ActivityResultRegistryOwner -> this
    is ContextWrapper -> baseContext.registryOwner()
    else -> null
}

private tailrec fun Context.activity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.activity()
    else -> null
}

/** The composer's round button: the field's height. */
private val BUTTON = 44.dp

/**
 * The round button at the composer's end, right of the field (operator, 2026-10-09: WhatsApp's layout; the emoji
 * button goes, the phone's keyboard has emoji). The microphone while there is nothing to send, the arrow once there
 * is; the one turns into the other on a spring. Tapped as the arrow, it sends. Held as the microphone, it records:
 * the circle grows under the finger and follows it, the lock rises over it ([VoiceHoldOverlay]); left far enough the
 * recording is thrown away, up far enough it locks; a short press asks to hold; with TalkBack a double tap records,
 * locked. The capsule over it says why nothing happened ([VoiceHintCapsule]). Without a [recorder] (the app declares
 * no microphone) it is the arrow, dimmed while there is nothing to send.
 */
@Composable
internal fun ComposerSendButton(
    canSend: Boolean,
    recorder: VoiceRecorder?,
    theme: ClomniTheme,
    strings: ClomniStrings,
    send: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val controller = recorder?.controller
    val mic = controller != null && !canSend
    val holding = recorder?.state as? State.Holding
    val density = LocalDensity.current.density
    val sendLatest by rememberUpdatedState(send)
    // 1 shows the microphone, 0 the arrow; between them both turn and fade (a 150 ms fade without motion).
    val shown by animateFloatAsState(if (mic) 1f else 0f, if (reduceMotion()) tween(150) else spring(0.6f, 500f), label = "mic")
    val label = strings[if (mic) Key.VOICE_RECORD else Key.SEND]
    val on = canSend || mic
    Box(
        modifier.bleed(2.dp, 2.dp).size(48.dp)
            .pointerInput(controller, mic) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    if (controller == null || !mic) {
                        if (waitForUpOrCancellation() != null && canSend) sendLatest()
                        return@awaitEachGesture
                    }
                    controller.press()
                    var lifted = false
                    try {
                        while (controller.state is State.Holding) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            lifted = !change.pressed
                            if (lifted) break
                            val moved = (change.position - down.position) / density
                            controller.drag(moved.x, moved.y)
                            change.consume()
                        }
                    } finally {
                        // Lifted, or the touch was taken away: either way the finger is no longer on the button.
                        if (lifted || controller.state is State.Holding) controller.release()
                    }
                }
            }
            .semantics {
                contentDescription = label
                role = Role.Button
                onClick(label) {
                    if (mic) controller?.pressLocked() else if (canSend) sendLatest()
                    true
                }
            }
            .padding(2.dp).alpha(if (holding != null) 0f else 1f)
            .background((if (on) theme.colors.primary else theme.colors.surface).color, CircleShape),
        Alignment.Center,
    ) {
        Icon(R.drawable.clomni_ic_mic, theme.colors.onPrimary, 22.dp, Modifier.turning(shown))
        Icon(R.drawable.clomni_ic_send_up, if (on) theme.colors.onPrimary else theme.colors.textSecondary, 20.dp, Modifier.turning(1 - shown))
        if (recorder != null) {
            if (holding != null) {
                Popup(alignment = Alignment.Center, properties = PopupProperties(clippingEnabled = false)) {
                    VoiceHoldOverlay(holding, recorder.controller.levels.lastOrNull() ?: 0f, theme)
                }
            }
            val hint = recorder.controller.hint
            if (hint != null) {
                val context = LocalContext.current
                Popup(Alignment.BottomEnd, IntOffset(0, -(56 * density).toInt()), recorder.controller::dismissHint, PopupProperties(clippingEnabled = false)) {
                    VoiceHintCapsule(hint, theme, strings, recorder.maxSeconds) { VoiceAudio.openSettings(context) }
                }
            }
        }
    }
}

/** Shown at [amount] 1, gone at 0: it grows from 0.6 and turns in from a quarter as it fades in. */
private fun Modifier.turning(amount: Float): Modifier = graphicsLayer {
    alpha = amount.coerceIn(0f, 1f)
    scaleX = 0.6f + 0.4f * amount
    scaleY = scaleX
    rotationZ = -90f * (1 - amount)
}

/** The hold overlay's square, centred on the button. */
internal const val VOICE_OVERLAY_DP = 320

/** [painter] drawn [size] px wide, centred on [center], in [color]; turned [degrees] about [pivot] (its centre). */
private fun DrawScope.icon(painter: Painter, color: Color, center: Offset, size: Float, degrees: Float = 0f, pivot: Offset = Offset(0.5f, 0.5f)) =
    translate(center.x - size / 2, center.y - size / 2) {
        rotate(degrees, Offset(size * pivot.x, size * pivot.y)) {
            with(painter) { draw(Size(size, size), colorFilter = ColorFilter.tint(color)) }
        }
    }

/**
 * Under the finger while it holds: the 72 dp circle with the microphone, grown from the button on a spring, following
 * the slide, a soft ring round it breathing with the voice; over it the lock in its capsule, rising as the finger goes
 * up, its shackle closing. Drawn centred on the button, in one canvas.
 */
@Composable
internal fun VoiceHoldOverlay(holding: State.Holding, level: Float, theme: ClomniTheme) {
    val still = reduceMotion() || LocalInspectionMode.current
    val grow = remember { Animatable(if (still) 1f else 0.5f) }
    LaunchedEffect(Unit) { grow.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = 420f)) }
    // The live level eases between ticks: a ring that jumped 20 times a second would flicker.
    val ring by animateFloatAsState(level, tween(90), label = "level")
    val colors = theme.colors
    val mic = painterResource(R.drawable.clomni_ic_mic)
    val body = painterResource(R.drawable.clomni_ic_lock_body)
    val shackle = painterResource(R.drawable.clomni_ic_lock_shackle)
    val up = painterResource(R.drawable.clomni_ic_chevron_up)
    Canvas(Modifier.size(VOICE_OVERLAY_DP.dp).clearAndSetSemantics {}) {
        val dp = density
        val middle = center
        val grey = colors.textSecondary.color
        // The capsule: 40 × 72, rising 34 more as it locks, fading as the finger goes left.
        val faded = (1f - holding.cancel * 1.5f).coerceIn(0f, 1f)
        val pill = Offset(middle.x - 20 * dp, middle.y - (120 + 34 * holding.lock) * dp)
        drawRoundRect(colors.background.color, pill, Size(40 * dp, 72 * dp), CornerRadius(20 * dp), alpha = faded)
        drawRoundRect(colors.border.color, pill, Size(40 * dp, 72 * dp), CornerRadius(20 * dp), Stroke(dp), faded)
        val lock = Offset(middle.x, pill.y + 21 * dp)
        icon(shackle, grey.copy(alpha = faded), lock + Offset(0f, -3 * dp * (1 - holding.lock)), 22 * dp)
        icon(body, grey.copy(alpha = faded), lock, 22 * dp)
        icon(up, grey.copy(alpha = faded * (1 - holding.lock)), Offset(middle.x, pill.y + 52 * dp), 18 * dp)
        // The microphone where the finger is.
        val at = middle + Offset(-holding.cancel * VoiceRecording.CANCEL_DP * dp, -holding.lock * VoiceRecording.LOCK_DP * dp)
        val radius = 36 * dp * grow.value
        drawCircle(colors.primary.color.copy(alpha = 0.22f), radius * (1f + 0.4f * ring), at)
        drawCircle(colors.primary.color, radius, at)
        icon(mic, colors.onPrimary.color, at, 30 * dp * grow.value)
    }
}

/** A dark capsule over the button: "Yazmaq üçün basıb saxlayın", the limit, or the refused microphone with its way out. */
@Composable
internal fun VoiceHintCapsule(hint: Hint, theme: ClomniTheme, strings: ClomniStrings, maxSeconds: Int, openSettings: () -> Unit) {
    val capsule = theme.capsule
    val text = when (hint) {
        Hint.HOLD -> strings[Key.VOICE_HOLD_TO_RECORD]
        Hint.LIMIT -> strings.format(Key.VOICE_MAX_LENGTH, maxOf(1, maxSeconds / 60))
        Hint.DENIED -> strings[Key.VOICE_MIC_DENIED]
    }
    Column(
        Modifier.padding(end = 8.dp).widthIn(max = 280.dp)
            .background(capsule.fill.color.copy(alpha = capsule.opacity.toFloat()), RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        BasicText(text, style = clomniText(ClomniTheme.FontSize.text, capsule.text, lineHeight = 1.3f))
        if (hint == Hint.DENIED) {
            val settings = strings[Key.VOICE_OPEN_SETTINGS]
            BasicText(
                settings,
                Modifier.padding(top = 6.dp).bleed(vertical = 12.dp).heightIn(min = 48.dp).button(settings, onClick = openSettings).padding(vertical = 13.dp),
                style = clomniText(ClomniTheme.FontSize.text, capsule.text, FontWeight.SemiBold),
            )
        }
    }
}

/**
 * What takes the field's place while a voice message is made, in the field's grey pill. Holding: the red dot
 * blinking, the timer and the live waveform, under them "‹ Ləğv etmək üçün sürüşdürün" going with the finger. Locked:
 * the same over Delete, Stop and Send. Stopped: the recording to listen to over Delete and Send. Thrown away: the
 * microphone falls into the bin, which closes and sinks.
 */
@Composable
internal fun VoiceRecordingBar(
    recorder: VoiceRecorder,
    playback: VoicePlayback,
    theme: ClomniTheme,
    strings: ClomniStrings,
    modifier: Modifier = Modifier,
) {
    val controller = recorder.controller
    val state = recorder.state
    val colors = theme.colors
    val still = reduceMotion() || LocalInspectionMode.current
    // One beat for the blinking dot and the hint's nudge.
    val beat by rememberInfiniteTransition(label = "beat")
        .animateFloat(0f, if (still) 0f else 1f, infiniteRepeatable(tween(550, easing = LinearEasing), RepeatMode.Reverse), label = "beat")
    // A recording starts: whatever voice message was playing pauses.
    LaunchedEffect(state is State.Holding || state is State.Locked) { if (state != State.Idle) playback.player.pause() }
    val clip = controller.review
    val grey = colors.textSecondary
    Column(modifier.fillMaxWidth().then(if (still) Modifier else Modifier.animateContentSize(spring(dampingRatio = 0.86f, stiffness = 500f)))) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).background(colors.surface.color, RoundedCornerShape(20.dp)).padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (state is State.Holding || state is State.Locked) {
                val elapsed = (state as? State.Holding)?.elapsedMs ?: (state as State.Locked).elapsedMs
                Spacer(Modifier.size(10.dp).alpha(1f - 0.8f * beat).background(colors.unread.color, CircleShape))
                BasicText(
                    VoiceTime.clock(elapsed),
                    Modifier.padding(start = 8.dp).widthIn(min = 40.dp),
                    style = clomniText(15f, colors.textPrimary, FontWeight.Medium).copy(fontFeatureSettings = "tnum"),
                )
                // The microphone under the finger covers the pill's end.
                val levels = controller.levels
                Canvas(Modifier.padding(start = 8.dp, end = if (state is State.Holding) 36.dp else 0.dp).weight(1f).height(24.dp)) {
                    drawBars(Waveform.live(levels, barCount()), 1f, grey.color, grey.color)
                }
            } else if (state is State.Review && clip != null) {
                val id = "voice-review-${clip.file.name}"
                val track = playback.track(id)
                val playing = track.phase == VoicePlayer.Phase.PLAYING
                RoundIcon(
                    strings[if (playing) Key.VOICE_PAUSE else Key.VOICE_PLAY], if (playing) R.drawable.clomni_ic_pause else R.drawable.clomni_ic_play,
                    colors.primaryText, Modifier.bleed(14.dp, 2.dp, 0.dp, 2.dp).padding(14.dp),
                ) { playback.player.toggle(id, VoicePlayer.Source.Local(clip.file), clip.durationMs) }
                WaveformBar(
                    clip.waveform, track.progress, colors.primaryText.color, grey.alpha(0.45f), track.phase != VoicePlayer.Phase.IDLE,
                    strings[Key.VOICE_MESSAGE], VoiceTime.length(clip.durationMs), { playback.player.seek(id, it, clip.durationMs) },
                    Modifier.padding(horizontal = 8.dp).weight(1f).height(28.dp),
                )
                BasicText(
                    if (track.positionMs > 0) VoiceTime.remaining(clip.durationMs - track.positionMs) else VoiceTime.length(clip.durationMs),
                    style = clomniText(13f, grey).copy(fontFeatureSettings = "tnum"),
                )
            } else if (recorder.dropping) {
                BinDrop(theme) { recorder.dropping = false }
            }
        }
        if (state is State.Holding) {
            BasicText(
                "‹  ${strings[Key.VOICE_SLIDE_TO_CANCEL]}",
                Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 2.dp).graphicsLayer {
                    translationX = (-state.cancel * 60f - 6 * beat).dp.toPx()
                    alpha = (1f - state.cancel * 1.4f).coerceIn(0f, 1f)
                },
                style = clomniText(13f, grey).copy(textAlign = TextAlign.Center),
                maxLines = 1,
            )
        } else if (state is State.Locked || state is State.Review) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                RoundIcon(strings[Key.VOICE_DELETE], R.drawable.clomni_ic_delete, grey, Modifier.padding(12.dp), onClick = controller::delete)
                if (state is State.Locked) {
                    RoundIcon(
                        strings[Key.VOICE_STOP], R.drawable.clomni_ic_stop, colors.unread,
                        Modifier.padding(6.dp).border(2.dp, colors.unread.color, CircleShape).padding(8.dp), onClick = controller::stop,
                    )
                }
                RoundIcon(
                    strings[Key.SEND], R.drawable.clomni_ic_send_up, colors.onPrimary,
                    Modifier.padding(2.dp).background(colors.primary.color, CircleShape).padding(12.dp), onClick = controller::send,
                )
            }
        }
    }
}

/** A 48 dp target with [icon] in [ink], the rest of its look in [inside] (a circle, a ring, padding to the icon). */
@Composable
private fun RoundIcon(label: String, icon: Int, ink: RgbColor, inside: Modifier, onClick: () -> Unit) {
    Image(
        painterResource(icon),
        null,
        Modifier.size(48.dp).button(label, CircleShape, BUTTON, onClick).then(inside),
        colorFilter = ColorFilter.tint(ink.color),
    )
}

/**
 * The microphone thrown away (WhatsApp's): the bin rises with its lid open, the red microphone jumps and falls in, the
 * lid shuts, the bin sinks. 1 s; without motion a fade. [done] when it is over. [frozenAt] holds one moment of it
 * (0–1), for the screenshots.
 */
@Composable
internal fun BinDrop(theme: ClomniTheme, frozenAt: Float? = null, done: () -> Unit) {
    val still = reduceMotion() && frozenAt == null
    val time = remember { Animatable(frozenAt ?: 0f) }
    if (frozenAt == null) {
        LaunchedEffect(Unit) {
            time.animateTo(1f, tween(if (still) 200 else 1000, easing = LinearEasing))
            done()
        }
    }
    val mic = painterResource(R.drawable.clomni_ic_mic)
    val bin = painterResource(R.drawable.clomni_ic_trash)
    val lid = painterResource(R.drawable.clomni_ic_trash_lid)
    val red = theme.colors.unread.color
    val grey = theme.colors.textSecondary.color
    Canvas(Modifier.size(40.dp, 44.dp).clearAndSetSemantics {}) {
        val t = time.value
        val dp = density
        if (still) return@Canvas icon(mic, red.copy(alpha = 1f - t), center, 20 * dp)
        // The bin: up in the first fifth, down in the last; its lid open while the microphone falls.
        val bottom = center + Offset(0f, (30 * (1 - ease(t / 0.2f)) + 30 * ease((t - 0.8f) / 0.2f)) * dp)
        val fade = ((1 - t) * 10).coerceAtMost(1f)
        icon(bin, grey.copy(alpha = fade), bottom, 24 * dp)
        icon(lid, grey.copy(alpha = fade), bottom, 24 * dp, -40f * (ease((t - 0.12f) / 0.13f) - ease((t - 0.62f) / 0.1f)), Offset(0.19f, 0.26f))
        // The microphone: up, then down into the bin, turning over and shrinking as it goes in.
        if (t < 0.6f) {
            val fall = center + Offset(0f, (-34 * ease(t / 0.3f) + 40 * ease((t - 0.3f) / 0.3f)) * dp)
            icon(mic, red, fall, 18 * dp * (1f - 0.5f * ease((t - 0.45f) / 0.15f)), 300f * t)
        }
    }
}

/** Ease in and out over 0–1; flat before and after. */
private fun ease(x: Float): Float {
    val p = x.coerceIn(0f, 1f)
    return p * p * (3 - 2 * p)
}

/** A theme colour with [alpha]. */
internal fun RgbColor.alpha(alpha: Float) = color.copy(alpha = alpha)
