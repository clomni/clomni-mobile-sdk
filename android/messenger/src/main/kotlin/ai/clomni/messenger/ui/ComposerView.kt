package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatComposer
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.VoiceRecording
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup

/** A file picked in the sheet, shown over the field until it is sent with the message, or removed. */
internal class PickedPreview(
    /** A picture's local address (a content Uri as text) for its thumbnail; null for another file. */
    val image: String?,
    val name: String,
)

/**
 * A white strip with the top hairline over the navigation bar, rising with the keyboard (DESIGN-PASS-2 11): a picked
 * file's 64 dp preview with its ×, then the field (surface, radius 20, at least 44 high, up to 5 lines, then it
 * scrolls) with the paper clip (24) inside it at the end, and right of it the round button (CM-130, operator
 * 2026-10-09, WhatsApp's layout; the emoji button went, the keyboard has emoji): the microphone while there is nothing
 * to send, the arrow once there is ([ComposerSendButton]). While a voice message is recorded its bar takes the field's
 * place ([VoiceRecordingBar]). A closed conversation offers a new one, and writing anyway reopens it. While a step
 * waits for a button there is no composer (see ChatScreenView).
 */
@Composable
internal fun ComposerView(
    composer: ChatComposer,
    theme: ClomniTheme,
    text: String,
    changeText: (String) -> Unit,
    writeAnyway: Boolean,
    setWriteAnyway: () -> Unit,
    actions: ChatActions,
    picked: PickedPreview? = null,
    focus: FocusRequester = remember { FocusRequester() },
) {
    Column(
        Modifier.fillMaxWidth().background(theme.colors.background.color)
            .windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.ime)),
    ) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        // M7: a quote, a picked file or another line of text: the bar's height follows over 220 ms (not without motion).
        val grows = if (reduceMotion()) Modifier else Modifier.animateContentSize(tween(220, easing = Motion.EmphasizedDecelerate))
        Column(Modifier.fillMaxWidth().then(grows).padding(horizontal = 16.dp, vertical = 8.dp)) {
            // The message being answered, over the field; the bar grows to it (animateContentSize, M7).
            composer.quote?.let { QuoteStrip(it, composer.cancelQuoteLabel, theme, actions.cancelReply) }
            // Answering puts the cursor in the field.
            LaunchedEffect(composer.quote?.messageId) {
                if (composer.quote != null && composer.mode == ChatComposer.Mode.Open) runCatching { focus.requestFocus() }
            }
            if (picked != null) {
                Preview(picked, composer.removeLabel, theme, actions.removePicked)
            }
            when (val mode = composer.mode) {
                // Not shown: ChatScreenView leaves the composer out while a step waits for a button.
                ChatComposer.Mode.Hidden -> Unit
                is ChatComposer.Mode.Closed -> if (writeAnyway) {
                    Writing(composer, theme, text, changeText, actions, focus, picked != null)
                    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
                } else {
                    Closed(mode, theme, actions.startNew) {
                        setWriteAnyway()
                    }
                }
                ChatComposer.Mode.Open -> Writing(composer, theme, text, changeText, actions, focus, picked != null)
            }
        }
    }
}

/** A picked file over the field: 64 dp, the picture itself or the file's icon, radius 12, × at its corner. */
@Composable
private fun Preview(picked: PickedPreview, removeLabel: String, theme: ClomniTheme, remove: () -> Unit) {
    Box(Modifier.padding(bottom = 8.dp)) {
        Box(
            Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)).background(theme.colors.surface.color)
                .semantics { contentDescription = picked.name },
            Alignment.Center,
        ) {
            if (picked.image != null && !LocalInspectionMode.current) {
                coil.compose.AsyncImage(
                    picked.image,
                    null,
                    ClomniImages.loader(LocalContext.current),
                    Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            } else {
                Icon(R.drawable.clomni_ic_file, theme.colors.textSecondary, 24.dp)
            }
        }
        // The × reaches a 48 dp target around its 20 dp circle at the corner.
        Box(Modifier.align(Alignment.TopEnd).offset(x = 18.dp, y = (-18).dp).size(48.dp).button(removeLabel, CircleShape, 32.dp, remove), Alignment.Center) {
            Box(Modifier.size(20.dp).clip(CircleShape).background(theme.colors.textPrimary.color), Alignment.Center) {
                Icon(R.drawable.clomni_ic_close, theme.colors.background, 14.dp)
            }
        }
    }
}

/** "Söhbət bağlanıb · Yeni söhbət başlat": the first writes anyway, the second starts a new conversation. */
@Composable
private fun Closed(mode: ChatComposer.Mode.Closed, theme: ClomniTheme, startNew: () -> Unit, writeAnyway: () -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(ClomniTheme.Space.xs.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val target = Modifier.heightIn(min = ClomniTheme.Size.touchTarget.dp)
        Box(target.button(mode.text, RoundedCornerShape(8.dp), onClick = writeAnyway), Alignment.Center) {
            BasicText(mode.text, style = clomniText(13f, theme.colors.textSecondary))
        }
        BasicText("·", Modifier.clearAndSetSemantics {}, style = clomniText(13f, theme.colors.textSecondary))
        Box(target.button(mode.action, RoundedCornerShape(8.dp), onClick = startNew), Alignment.Center) {
            BasicText(mode.action, style = clomniText(13f, theme.colors.primaryText, FontWeight.SemiBold))
        }
    }
}

/**
 * The field and the round button right of it; while a voice message is made, its bar in the field's place. Locked or
 * stopped, the bar has its own Send, and the button goes; while the finger holds it stays, under the finger.
 */
@Composable
private fun Writing(
    composer: ChatComposer,
    theme: ClomniTheme,
    text: String,
    changeText: (String) -> Unit,
    actions: ChatActions,
    focus: FocusRequester,
    hasPicked: Boolean,
) {
    val recorder = LocalVoiceRecorder.current
    val playback = LocalVoicePlayback.current
    val state = recorder?.state
    val holding = state is VoiceRecording.State.Holding
    Row(verticalAlignment = if (holding) Alignment.Top else Alignment.Bottom) {
        if (recorder != null && playback != null && recorder.showsBar) {
            VoiceRecordingBar(recorder, playback, theme, composer.texts, Modifier.weight(1f))
        } else {
            Field(composer, theme, text, changeText, actions, focus, Modifier.weight(1f))
        }
        if (state !is VoiceRecording.State.Locked && state !is VoiceRecording.State.Review && recorder?.dropping != true) {
            val canSend = hasPicked || ChatPresenter.canSend(text, composer.limit)
            ComposerSendButton(canSend, recorder, theme, composer.texts, actions.send, Modifier.padding(start = 8.dp))
        }
    }
}

@Composable
private fun Field(
    composer: ChatComposer,
    theme: ClomniTheme,
    text: String,
    changeText: (String) -> Unit,
    actions: ChatActions,
    focus: FocusRequester,
    modifier: Modifier,
) {
    var sheet by remember { mutableStateOf(false) }
    // The field keeps its cursor; the text itself is the screen's.
    var field by remember { mutableStateOf(TextFieldValue(text, TextRange(text.length))) }
    if (field.text != text) field = TextFieldValue(text, TextRange(text.length))
    // The field is the 44 dp grey box; its target is 48, 2 dp of it above and below laying out over the bar's padding.
    val slack = (ClomniTheme.Size.touchTarget.dp - 44.dp) / 2
    BasicTextField(
        field,
        {
            field = it
            if (it.text != text) changeText(it.text)
        },
        modifier.bleed(vertical = slack).heightIn(min = ClomniTheme.Size.touchTarget.dp)
            .focusRequester(focus).semantics { contentDescription = composer.placeholder },
        textStyle = clomniText(16f, theme.colors.textPrimary),
        maxLines = 5,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        cursorBrush = SolidColor(theme.colors.primary.color),
        decorationBox = { inner ->
            Row(
                Modifier.padding(vertical = slack).heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(theme.colors.surface.color)
                    .padding(start = 16.dp, end = if (composer.showsAttach) 4.dp else 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f).padding(vertical = 10.dp), contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) {
                        BasicText(
                            composer.placeholder,
                            style = clomniText(16f, theme.colors.textSecondary),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    inner()
                }
                if (composer.showsAttach) IconButton(R.drawable.clomni_ic_attach, composer.attachLabel, theme) { sheet = true }
            }
        },
    )
    if (sheet) {
        AttachmentSheet(composer, theme, actions) { sheet = false }
    }
}

/** A 24 dp icon in a 40 dp slot (its target reaches 48). */
@Composable
private fun IconButton(icon: Int, label: String, theme: ClomniTheme, action: () -> Unit) {
    val inset = (ClomniTheme.Size.touchTarget.dp - 40.dp) / 2
    Box(Modifier.bleed(inset, inset).size(ClomniTheme.Size.touchTarget.dp).button(label, CircleShape, 40.dp, action), Alignment.Center) {
        Icon(icon, theme.colors.textSecondary, 24.dp)
    }
}
