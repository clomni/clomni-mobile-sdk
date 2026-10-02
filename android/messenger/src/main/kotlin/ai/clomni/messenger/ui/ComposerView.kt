package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatComposer
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ClomniTheme
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

/**
 * A white strip with the top hairline over the navigation bar (and the keyboard): the field (surface, radius 20, 38
 * high, up to 5 lines), the emoji and attach icons while it is empty, and the primary send button (34) once there is
 * text. A step waiting for a button locks it; a closed conversation offers a new one, and writing anyway reopens it.
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
    focus: FocusRequester = remember { FocusRequester() },
) {
    Column(
        Modifier.fillMaxWidth().background(theme.colors.background.color)
            .windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.ime)),
    ) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(theme.colors.border.color))
        Box(Modifier.fillMaxWidth().padding(horizontal = ClomniTheme.Space.l.dp, vertical = ClomniTheme.Space.s.dp)) {
            when (val mode = composer.mode) {
                is ChatComposer.Mode.Locked -> BasicText(
                    mode.text,
                    Modifier.fillMaxWidth().heightIn(min = 38.dp)
                        .clip(RoundedCornerShape(ClomniTheme.Radius.input.dp))
                        .background(theme.colors.surface.color)
                        .padding(horizontal = ClomniTheme.Space.l.dp, vertical = 10.dp),
                    style = clomniText(13f, theme.colors.textSecondary).copy(textAlign = TextAlign.Center),
                )
                is ChatComposer.Mode.Closed -> if (writeAnyway) {
                    Field(composer, theme, text, changeText, actions, focus)
                    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
                } else {
                    Closed(mode, theme, actions.startNew) {
                        setWriteAnyway()
                    }
                }
                ChatComposer.Mode.Open -> Field(composer, theme, text, changeText, actions, focus)
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
        Box(target.button(mode.text, writeAnyway), Alignment.Center) {
            BasicText(mode.text, style = clomniText(13f, theme.colors.textSecondary))
        }
        BasicText("·", Modifier.clearAndSetSemantics {}, style = clomniText(13f, theme.colors.textSecondary))
        Box(target.button(mode.action, startNew), Alignment.Center) {
            BasicText(mode.action, style = clomniText(13f, theme.colors.primary, FontWeight.SemiBold))
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
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val canSend = ChatPresenter.canSend(text, composer.limit)
    // The field is the 38 dp grey box, but takes taps (and TalkBack's frame) over 48: 5 dp of it above and below the
    // box lay out over the bar's own padding.
    val slack = (ClomniTheme.Size.touchTarget.dp - 38.dp) / 2
    Row(verticalAlignment = Alignment.Bottom) {
        BasicTextField(
            text,
            changeText,
            Modifier.weight(1f).bleed(vertical = slack).heightIn(min = ClomniTheme.Size.touchTarget.dp)
                .focusRequester(focus).semantics { contentDescription = composer.placeholder },
            textStyle = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary),
            maxLines = 5,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            cursorBrush = SolidColor(theme.colors.primary.color),
            decorationBox = { inner ->
                Row(
                    Modifier.padding(vertical = slack).heightIn(min = 38.dp)
                        .clip(RoundedCornerShape(ClomniTheme.Radius.input.dp))
                        .background(theme.colors.surface.color)
                        .padding(horizontal = ClomniTheme.Space.l.dp, vertical = ClomniTheme.Space.s.dp),
                    horizontalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                        if (text.isEmpty()) {
                            BasicText(
                                composer.placeholder,
                                style = clomniText(ClomniTheme.FontSize.text, theme.colors.textSecondary),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        inner()
                    }
                    if (text.isEmpty()) {
                        if (composer.showsEmoji) {
                            IconButton(R.drawable.clomni_ic_emoji, composer.emojiLabel, theme) {
                                // The keyboard's own emoji key does the rest.
                                focus.requestFocus()
                                keyboard?.show()
                            }
                        }
                        if (composer.showsAttach) AttachButton(composer, theme, actions)
                    }
                }
            },
        )
        AnimatedVisibility(canSend, enter = fadeIn(tween(200)), exit = fadeOut(tween(200))) {
            val inset = (ClomniTheme.Size.touchTarget.dp - 34.dp) / 2
            Box(
                Modifier.padding(start = ClomniTheme.Space.s.dp, bottom = 2.dp)
                    .bleed(inset, inset).size(ClomniTheme.Size.touchTarget.dp).button(composer.sendLabel, actions.send),
                Alignment.Center,
            ) {
                Box(Modifier.size(34.dp).clip(CircleShape).background(theme.colors.primary.color), Alignment.Center) {
                    Icon(R.drawable.clomni_ic_send_up, theme.colors.onPrimary, 15.dp)
                }
            }
        }
    }
}

/** A 19 dp icon in a 48 dp target that lays out at the icon's size. */
@Composable
private fun IconButton(icon: Int, label: String, theme: ClomniTheme, action: () -> Unit) {
    val inset = (ClomniTheme.Size.touchTarget.dp - 19.dp) / 2
    Box(Modifier.bleed(inset, inset).size(ClomniTheme.Size.touchTarget.dp).button(label, action), Alignment.Center) {
        Icon(icon, theme.colors.textSecondary, 19.dp)
    }
}

/** The paper clip opens a small menu: a picture (Photo Picker) or any file. */
@Composable
private fun AttachButton(composer: ChatComposer, theme: ClomniTheme, actions: ChatActions) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(R.drawable.clomni_ic_attach, composer.attachLabel, theme) { open = true }
        if (open) {
            val shape = RoundedCornerShape(ClomniTheme.Radius.card.dp)
            Popup(
                alignment = Alignment.BottomEnd,
                offset = IntOffset(0, -56),
                onDismissRequest = { open = false },
                properties = PopupProperties(focusable = true),
            ) {
                Column(
                    Modifier.widthIn(min = 160.dp).clip(shape).background(theme.colors.background.color)
                        .border(1.dp, theme.colors.border.color, shape),
                ) {
                    for ((label, pick) in listOf(composer.imageLabel to actions.pickImage, composer.fileLabel to actions.pickFile)) {
                        Box(
                            Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp)
                                .button(label) {
                                    open = false
                                    pick()
                                }
                                .padding(horizontal = ClomniTheme.Space.l.dp),
                            Alignment.CenterStart,
                        ) {
                            BasicText(label, style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary))
                        }
                    }
                }
            }
        }
    }
}
