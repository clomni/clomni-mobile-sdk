package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ChatComposer
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ClomniTheme
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
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
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
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
 * scrolls) with the emoji and attach icons (24) inside it at the end; once there is something to send, the 36 dp send
 * button in the brand colour takes the attach icon's place (150 ms, scale and fade). A closed conversation offers a new
 * one, and writing anyway reopens it. While a step waits for a button there is no composer (see ChatScreenView).
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
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            // The message being answered, over the field; it comes and goes by growing and fading.
            var shownQuote by remember { mutableStateOf(composer.quote) }
            if (composer.quote != null) shownQuote = composer.quote
            AnimatedVisibility(
                composer.quote != null,
                enter = expandVertically(tween(220, easing = FastOutSlowInEasing)) + fadeIn(tween(220)),
                exit = shrinkVertically(tween(180, easing = FastOutSlowInEasing)) + fadeOut(tween(180)),
            ) {
                shownQuote?.let { QuoteStrip(it, composer.cancelQuoteLabel, theme, actions.cancelReply) }
            }
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
                    Field(composer, theme, text, changeText, actions, focus, picked != null)
                    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
                } else {
                    Closed(mode, theme, actions.startNew) {
                        setWriteAnyway()
                    }
                }
                ChatComposer.Mode.Open -> Field(composer, theme, text, changeText, actions, focus, picked != null)
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

@Composable
private fun Field(
    composer: ChatComposer,
    theme: ClomniTheme,
    text: String,
    changeText: (String) -> Unit,
    actions: ChatActions,
    focus: FocusRequester,
    hasPicked: Boolean,
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val canSend = hasPicked || ChatPresenter.canSend(text, composer.limit)
    var sheet by remember { mutableStateOf(false) }
    var emoji by remember { mutableStateOf(false) }
    // The field keeps its cursor, so a picked emoji goes where the cursor is; the text itself is the screen's.
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
        Modifier.fillMaxWidth().bleed(vertical = slack).heightIn(min = ClomniTheme.Size.touchTarget.dp)
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
                    .padding(start = 16.dp, end = 4.dp),
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
                if (composer.showsEmoji) {
                    IconButton(R.drawable.clomni_ic_emoji, composer.emojiLabel, theme) {
                        keyboard?.hide()
                        emoji = true
                    }
                }
                // Send takes the attach icon's place once there is something to send.
                AnimatedContent(
                    canSend,
                    transitionSpec = {
                        (scaleIn(tween(150), initialScale = 0.6f) + fadeIn(tween(150))) togetherWith
                            (scaleOut(tween(150), targetScale = 0.6f) + fadeOut(tween(150)))
                    },
                    label = "send",
                ) { sending ->
                    when {
                        sending -> SendButton(composer.sendLabel, theme, actions.send)
                        composer.showsAttach -> IconButton(R.drawable.clomni_ic_attach, composer.attachLabel, theme) { sheet = true }
                        else -> Spacer(Modifier.size(0.dp))
                    }
                }
            }
        },
    )
    if (sheet) {
        AttachmentSheet(composer, theme, actions) { sheet = false }
    }
    if (emoji) {
        EmojiSheet(theme, pick = { picked ->
            val at = field.selection
            val next = field.text.replaceRange(at.min, at.max, picked)
            field = TextFieldValue(next, TextRange(at.min + picked.length))
            changeText(next)
        }) { emoji = false }
    }
}

/** 36 dp circle in the brand colour with the white arrow, in a 40 dp slot (its target reaches 48). */
@Composable
private fun SendButton(label: String, theme: ClomniTheme, send: () -> Unit) {
    val inset = (ClomniTheme.Size.touchTarget.dp - 40.dp) / 2
    Box(Modifier.bleed(inset, inset).size(ClomniTheme.Size.touchTarget.dp).button(label, CircleShape, 40.dp, send), Alignment.Center) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(theme.colors.primary.color), Alignment.Center) {
            Icon(R.drawable.clomni_ic_send_up, theme.colors.onPrimary, 18.dp)
        }
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
