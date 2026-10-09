package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.FakeFiles
import ai.clomni.messenger.presentation.FakeMic
import ai.clomni.messenger.presentation.FakeOutput
import ai.clomni.messenger.presentation.FakeTime
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.VoiceNote
import ai.clomni.messenger.presentation.VoicePlayer
import ai.clomni.messenger.presentation.VoicePlayer.Phase
import ai.clomni.messenger.presentation.VoicePlayer.Track
import ai.clomni.messenger.presentation.VoiceRecorderController
import ai.clomni.messenger.presentation.VoiceRecording
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Voice messages (CM-130), light and dark: the bubble in each of its states on both sides, at twice the text size,
 * and the recorder: held (the big microphone under the finger, the lock over it), locked, stopped for listening, the
 * bin, and the capsules. Each also checks the 48 dp tap targets.
 */
class VoiceSnapshotTest {
    private val semantics = SemanticsCapture()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderingMode = SessionParams.RenderingMode.SHRINK,
        renderExtensions = setOf(semantics),
    )

    @get:Rule
    val folder = TemporaryFolder()

    private val strings = ClomniStrings("az")
    private val config = Fixture.exampleConfig
    private val voice = ProtocolJson().parseMessage(ProtocolFiles.read("fixtures/100-audio-voice-user.json"))!!.content as MessageContent.Audio
    private val operator = ProtocolJson().parseMessage(ProtocolFiles.read("fixtures/101-audio-operator-no-waveform.json"))!!.content as MessageContent.Audio

    private fun theme(dark: Boolean) = ClomniTheme.make(config.brand, dark)

    private fun snap(name: String, dark: Boolean, content: @Composable (ClomniTheme) -> Unit) {
        val theme = theme(dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                Box(Modifier.background(theme.colors.background.color).padding(16.dp)) { content(theme) }
            }
        }
        semantics.assertTouchTargets(name)
    }

    @Test
    fun bubbles() {
        for (dark in listOf(false, true)) snap("voice_bubbles_${if (dark) "dark" else "light"}", dark) { Bubbles(it) }
    }

    @Test
    fun bubblesAtTwiceTheTextSize() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 2f))
        snap("voice_bubbles_font_scale_200", dark = false) { Bubbles(it, short = true) }
    }

    @Test
    fun recorderHeld() {
        for (dark in listOf(false, true)) {
            val (recorder, _) = recorder()
            recorder.controller.press()
            time.advance(4_200)
            recorder.controller.drag(-36f, -30f)
            snap("voice_recorder_held_${if (dark) "dark" else "light"}", dark) { theme ->
                val held = recorder.controller.state as VoiceRecording.State.Holding
                Box(Modifier.width(360.dp).height(330.dp)) {
                    Composer(theme, Modifier.align(Alignment.BottomStart)) { VoiceRecordingBar(recorder, playback(), theme, strings, it) }
                    // The overlay as the popup draws it: centred on the microphone's slot at the composer's end.
                    Box(
                        Modifier.align(Alignment.BottomEnd)
                            .offset(x = (VOICE_OVERLAY_DP / 2 - 24).dp, y = (VOICE_OVERLAY_DP / 2 - 32).dp),
                    ) { VoiceHoldOverlay(held, 0.6f, theme) }
                }
            }
        }
    }

    @Test
    fun recorderLockedStoppedBinAndCapsules() {
        for (dark in listOf(false, true)) {
            val (locked, _) = recorder()
            locked.controller.pressLocked()
            time.advance(12_300)
            val (stopped, _) = recorder()
            stopped.controller.pressLocked()
            time.advance(9_000)
            stopped.controller.stop()
            snap("voice_recorder_states_${if (dark) "dark" else "light"}", dark) { theme ->
                Column(Modifier.width(360.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Composer(theme) { VoiceRecordingBar(locked, playback(), theme, strings, it) }
                    Composer(theme) { VoiceRecordingBar(stopped, playback(), theme, strings, it) }
                    Composer(theme) { modifier ->
                        Row(modifier.height(44.dp).clip(RoundedCornerShape(20.dp)).background(theme.colors.surface.color).padding(horizontal = 14.dp)) {
                            BinDrop(theme, frozenAt = 0.5f) {}
                        }
                    }
                    for (hint in VoiceRecorderController.Hint.entries) {
                        Box(Modifier.fillMaxWidth(), Alignment.CenterEnd) { VoiceHintCapsule(hint, theme, strings, 300) {} }
                    }
                }
            }
        }
    }

    /**
     * The composer's new end (operator, 2026-10-09): the field with the paper clip in it, and right of it the round
     * button: the microphone while empty, the arrow with text; without a microphone, the arrow dimmed.
     */
    @Test
    fun composerButton() {
        for (dark in listOf(false, true)) {
            val (recorder, _) = recorder()
            snap("voice_composer_${if (dark) "dark" else "light"}", dark) { theme ->
                Column(Modifier.width(360.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    for ((text, mic) in listOf("" to true, "Salam" to true, "" to false)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Row(
                                Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(20.dp)).background(theme.colors.surface.color)
                                    .padding(start = 16.dp, end = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                BasicText(
                                    text.ifEmpty { strings[ClomniStrings.Key.COMPOSER_PLACEHOLDER] },
                                    Modifier.weight(1f),
                                    style = clomniText(16f, if (text.isEmpty()) theme.colors.textSecondary else theme.colors.textPrimary),
                                )
                                Icon(R.drawable.clomni_ic_attach, theme.colors.textSecondary, 24.dp)
                            }
                            Spacer(Modifier.width(8.dp))
                            ComposerSendButton(text.isNotEmpty(), recorder.takeIf { mic }, theme, strings, send = {})
                        }
                    }
                }
            }
        }
    }

    private val time = FakeTime()

    private fun recorder(): Pair<VoiceRecorder, FakeMic> {
        val mic = FakeMic(time)
        var level = 0
        val controller = VoiceRecorderController(
            mic = object : ai.clomni.messenger.presentation.MicInput by mic {
                // A voice: loud and quiet in turn.
                override fun level(): Float = listOf(0.2f, 0.7f, 0.9f, 0.5f, 0.3f, 0.8f, 0.1f)[level++ % 7]
            },
            permission = { VoiceRecording.Permission.GRANTED },
            askPermission = {},
            newFile = { folder.newFile() },
            scheduler = time,
            now = { time.now },
            maxMs = 300_000,
            send = {},
        )
        return VoiceRecorder(controller, 300) to mic
    }

    private fun playback() = VoicePlayback(VoicePlayer(FakeFiles(), FakeOutput(), FakeTime()))

    /** The composer's row as the conversation draws it: the bar where the field is, the 48 dp slot at the end. */
    @Composable
    private fun Composer(theme: ClomniTheme, modifier: Modifier = Modifier, bar: @Composable (Modifier) -> Unit) {
        Row(modifier.width(360.dp).background(theme.colors.background.color).padding(vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            bar(Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            Box(Modifier.size(48.dp))
        }
    }

    /** Both sides, every state: ready, playing at 1.5×, paused half-heard, without a waveform, uploading, broken. */
    @Composable
    private fun Bubbles(theme: ClomniTheme, short: Boolean = false) {
        val mine = VoiceNote.of("msg_f100", voice, outgoing = true)
        val theirs = VoiceNote.of("msg_f101", operator, outgoing = false)
        val heard = VoiceNote.of("msg_f102", voice, outgoing = false)
        val rows = listOf(
            Triple(mine, Track(), VoicePlayer.Speed.NORMAL),
            Triple(mine, Track(Phase.PLAYING, 5_800, 14_260), VoicePlayer.Speed.FAST),
            Triple(heard, Track(Phase.PAUSED, 8_900, 14_260), VoicePlayer.Speed.FAST),
            Triple(theirs, Track(durationMs = 61_000), VoicePlayer.Speed.NORMAL),
            Triple(theirs.copy(id = "loading"), Track(Phase.LOADING, 0, 61_000), VoicePlayer.Speed.NORMAL),
            Triple(VoiceNote.sending("client-1", folder.root.resolve("v.m4a"), 3_400, voice.waveform, uploading = true), Track(), VoicePlayer.Speed.NORMAL),
            Triple(theirs.copy(id = "broken"), Track(Phase.FAILED), VoicePlayer.Speed.NORMAL),
        ).let { if (short) it.take(3) else it }
        Column(Modifier.width(360.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((note, track, speed) in rows) {
                Box(Modifier.fillMaxWidth(), if (note.outgoing) Alignment.CenterEnd else Alignment.CenterStart) {
                    val fill = if (note.outgoing) theme.colors.primary else theme.colors.surface
                    val ink = if (note.outgoing) theme.colors.onPrimary else theme.colors.textSecondary
                    VoiceMessageContent(
                        note,
                        track,
                        speed,
                        theme,
                        strings,
                        toggle = {},
                        seek = {},
                        cycleSpeed = {},
                        meta = { Meta(note.outgoing, ink) },
                        modifier = Modifier.widthIn(max = 281.dp)
                            .clip(RoundedCornerShape(ClomniTheme.Radius.message.dp, ClomniTheme.Radius.message.dp, if (note.outgoing) 5.dp else 18.dp, if (note.outgoing) 18.dp else 5.dp))
                            .background(fill.color),
                    )
                }
            }
        }
    }

    /** The bubble's time and ✓✓, as the conversation draws them (BubbleMeta). */
    @Composable
    private fun Meta(outgoing: Boolean, ink: ai.clomni.messenger.presentation.RgbColor) {
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText("10:31", style = clomniText(ClomniTheme.FontSize.meta, ink, lineHeight = 1.2f))
            if (outgoing) Icon(R.drawable.clomni_ic_check_double, ink, 15.dp, Modifier.size(15.dp, 8.dp))
        }
    }
}
