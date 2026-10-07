package ai.clomni.messenger.ui

import ai.clomni.messenger.R
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.FormCard
import ai.clomni.messenger.protocol.MessageContent.FormFieldType
import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import java.util.Calendar
import java.util.Locale

/**
 * A form as Intercom draws one: the bot's text in its bubble, then a card of its own under it (radius 16, 1 dp border,
 * padding 16). Labels 13 medium in the muted grey, "(istəyə görə)" after an optional one; fields 44 high on the canvas
 * grey without a border until focused (1.5 dp brand); the full-width brand "Göndər". Sent, the card keeps only the
 * values as lines and a small ✓.
 */
@Composable
internal fun FormCardView(
    card: FormCard,
    theme: ClomniTheme,
    bubble: Modifier,
    submit: (Map<String, String>) -> Map<String, String>,
) {
    val values = rememberSaveable(card.messageId, saver = mapSaver()) {
        mutableStateMapOf<String, String>().apply { card.fields.forEach { put(it.id, it.initialValue) } }
    }
    val errors = rememberSaveable(card.messageId, saver = mapSaver()) { mutableStateMapOf<String, String>() }
    var sent by rememberSaveable(card.messageId) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.s.dp)) {
        card.text?.let {
            BasicText(
                attributedText(it, theme.colors.primaryText),
                bubble.padding(vertical = ClomniTheme.Space.s.dp, horizontal = ClomniTheme.Space.l.dp)
                    .clearAndSetSemantics { contentDescription = card.textAccessibilityLabel },
                style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary),
            )
        }
        val cardShape = RoundedCornerShape(16.dp)
        Column(
            Modifier.fillMaxWidth().clip(cardShape).background(theme.colors.background.color)
                .border(1.dp, theme.colors.border.color, cardShape).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (card.readOnly && card.submitted.isNotEmpty()) {
                for (line in card.submitted) {
                    Column(Modifier.semantics(mergeDescendants = true) {}) {
                        BasicText(line.label, style = clomniText(13f, theme.colors.textSecondary, FontWeight.Medium))
                        BasicText(line.value, Modifier.padding(top = 2.dp), style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary))
                    }
                }
                card.sentLabel?.let { label ->
                    Box(Modifier.clearAndSetSemantics { contentDescription = label }) {
                        Icon(R.drawable.clomni_ic_check, theme.colors.textSecondary, 14.dp)
                    }
                }
            } else {
                for (field in card.fields) {
                    FormFieldView(field, values[field.id].orEmpty(), errors[field.id], card.readOnly || sent, theme) { value ->
                        values[field.id] = value
                        errors.remove(field.id)
                    }
                }
                if (!card.readOnly) {
                    val enabled = !sent
                    val shape = RoundedCornerShape(10.dp)
                    Box(
                        Modifier.fillMaxWidth().fieldBox(theme.colors.primary.color.copy(alpha = if (enabled) 1f else 0.6f))
                            .let { box ->
                                if (!enabled) box else box.button(card.submitTitle, shape) {
                                    val found = submit(values.toMap())
                                    errors.clear()
                                    errors.putAll(found)
                                    sent = found.isEmpty()
                                }
                            },
                        Alignment.Center,
                    ) {
                        BasicText(card.submitTitle, style = clomniText(15f, theme.colors.onPrimary, FontWeight.SemiBold))
                    }
                }
            }
        }
    }
}

private fun mapSaver() = androidx.compose.runtime.saveable.Saver<androidx.compose.runtime.snapshots.SnapshotStateMap<String, String>, Any>(
    save = { HashMap(it) },
    restore = { saved ->
        mutableStateMapOf<String, String>().apply {
            @Suppress("UNCHECKED_CAST")
            putAll(saved as Map<String, String>)
        }
    },
)

/** One field by its type: text, textarea, phone, email, number, select, date. */
@Composable
private fun FormFieldView(
    field: FormCard.Field,
    value: String,
    error: String?,
    disabled: Boolean,
    theme: ClomniTheme,
    change: (String) -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    val edge = when {
        error != null -> theme.colors.unread.color
        focused -> theme.colors.primary.color
        else -> Color.Transparent
    }
    val frame = Modifier.fillMaxWidth().fieldBox(theme.colors.canvas.color, edge, if (field.type == FormFieldType.TEXTAREA) 72.dp else 44.dp)
        .onFocusChanged { focused = it.isFocused }
    val text = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary)
    val hint = clomniText(ClomniTheme.FontSize.text, theme.colors.textSecondary)
    // G4: the field with the cursor, its label and its error stay over the keyboard as it rises, frame by frame.
    val requester = remember { BringIntoViewRequester() }
    val ime = WindowInsets.ime
    val density = LocalDensity.current
    LaunchedEffect(focused) {
        if (focused) snapshotFlow { ime.getBottom(density) }.collect { requester.bringIntoView() }
    }
    Column(Modifier.bringIntoViewRequester(requester), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // Read with the field itself ("Ad, soyad, məcburi"), not as a line of its own.
        BasicText(
            field.shownLabel,
            Modifier.clearAndSetSemantics {},
            style = clomniText(13f, theme.colors.textSecondary, FontWeight.Medium),
        )
        val described = Modifier.semantics {
            contentDescription = field.accessibilityLabel
            if (error != null) error(error)
        }
        when (field.type) {
            FormFieldType.SELECT -> Choice(
                field.label,
                field.options.firstOrNull { it.value == value }?.label,
                field.placeholder,
                field.options.map { it.value to it.label },
                disabled,
                theme,
                frame.then(described),
                change,
            )
            FormFieldType.DATE -> DateChoice(field.label, value, field.placeholder, disabled, theme, frame.then(described), change)
            else -> BasicTextField(
                value,
                { change(field.maxLength?.let { limit -> it.take(limit + 1) } ?: it) },
                // The padding is inside the decoration, so the whole frame is the field: a 48 dp target.
                frame.then(described),
                enabled = !disabled,
                textStyle = text,
                singleLine = field.type != FormFieldType.TEXTAREA,
                minLines = if (field.type == FormFieldType.TEXTAREA) 3 else 1,
                keyboardOptions = keyboard(field),
                cursorBrush = SolidColor(theme.colors.primary.color),
                decorationBox = { inner ->
                    Box(
                        Modifier.padding(horizontal = ClomniTheme.Space.m.dp, vertical = ClomniTheme.Space.s.dp),
                        contentAlignment = if (field.type == FormFieldType.TEXTAREA) Alignment.TopStart else Alignment.CenterStart,
                    ) {
                        if (value.isEmpty()) field.placeholder?.let { BasicText(it, style = hint, maxLines = 1) }
                        inner()
                    }
                },
            )
        }
        error?.let { BasicText(it, style = clomniText(ClomniTheme.FontSize.label, theme.colors.errorText)) }
    }
}

private fun keyboard(field: FormCard.Field) = when (field.type) {
    FormFieldType.PHONE -> KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next)
    FormFieldType.EMAIL -> KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Email, imeAction = ImeAction.Next)
    FormFieldType.NUMBER -> KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Next)
    FormFieldType.TEXTAREA -> KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
    else -> KeyboardOptions(
        capitalization = if (field.id == "name") KeyboardCapitalization.Words else KeyboardCapitalization.Sentences,
        imeAction = ImeAction.Next,
    )
}

/** A select field: the chosen option or the placeholder, ▾; a tap lists the options. */
@Composable
private fun Choice(
    name: String,
    chosen: String?,
    placeholder: String?,
    options: List<Pair<String, String>>,
    disabled: Boolean,
    theme: ClomniTheme,
    modifier: Modifier,
    change: (String) -> Unit,
) {
    var open by rememberSaveable { mutableStateOf(false) }
    Box(modifier.let { if (disabled) it else it.button("$name, ${chosen ?: placeholder.orEmpty()}", RoundedCornerShape(10.dp)) { open = true } }) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp).padding(horizontal = ClomniTheme.Space.m.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(
                chosen ?: placeholder.orEmpty(),
                Modifier.weight(1f),
                style = clomniText(ClomniTheme.FontSize.text, if (chosen == null) theme.colors.textSecondary else theme.colors.textPrimary),
                maxLines = 1,
            )
            Icon(R.drawable.clomni_ic_chevron_down, theme.colors.textSecondary, 16.dp)
        }
        if (open) {
            Popup(onDismissRequest = { open = false }, properties = PopupProperties(focusable = true)) {
                Column(
                    Modifier.widthIn(min = 160.dp, max = 260.dp)
                        .clip(RoundedCornerShape(ClomniTheme.Radius.card.dp))
                        .background(theme.colors.background.color)
                        .border(1.dp, theme.colors.border.color, RoundedCornerShape(ClomniTheme.Radius.card.dp)),
                ) {
                    for ((value, label) in options) {
                        Box(
                            Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp)
                                .button(label) {
                                    change(value)
                                    open = false
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

/** A date field: "yyyy-MM-dd" from the platform's date picker. */
@Composable
private fun DateChoice(
    name: String,
    value: String,
    placeholder: String?,
    disabled: Boolean,
    theme: ClomniTheme,
    modifier: Modifier,
    change: (String) -> Unit,
) {
    val context = LocalContext.current
    val pick = {
        val calendar = Calendar.getInstance()
        val parts = value.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size == 3) calendar.set(parts[0], parts[1] - 1, parts[2])
        DatePickerDialog(
            context,
            { _, year, month, day -> change(String.format(Locale.ROOT, "%04d-%02d-%02d", year, month + 1, day)) },
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH),
            calendar.get(Calendar.DAY_OF_MONTH),
        ).show()
    }
    Box(
        modifier.let { if (disabled) it else it.button("$name, ${value.ifEmpty { placeholder.orEmpty() }}", RoundedCornerShape(10.dp)) { pick() } }
            .padding(horizontal = ClomniTheme.Space.m.dp),
        Alignment.CenterStart,
    ) {
        BasicText(
            value.ifEmpty { placeholder.orEmpty() },
            style = clomniText(ClomniTheme.FontSize.text, if (value.isEmpty()) theme.colors.textSecondary else theme.colors.textPrimary),
        )
    }
}

/**
 * A field or the send button: [height] (44) drawn with radius 10 in [fill], [edge] 1.5 dp around it, while the tap
 * target reaches 48 (2 dp above and below, laid over the 12 dp gaps).
 */
internal fun Modifier.fieldBox(fill: Color, edge: Color = Color.Transparent, height: Dp = 44.dp): Modifier =
    bleed(vertical = 2.dp).heightIn(min = height + 4.dp).drawBehind {
        val inset = 2.dp.toPx()
        val corner = CornerRadius(10.dp.toPx())
        val area = Size(size.width, size.height - inset * 2)
        drawRoundRect(fill, Offset(0f, inset), area, corner)
        if (edge.alpha > 0f) {
            val half = 0.75.dp.toPx()
            drawRoundRect(edge, Offset(half, inset + half), Size(area.width - half * 2, area.height - half * 2), corner, Stroke(half * 2))
        }
    }
