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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import java.util.Calendar
import java.util.Locale

/**
 * A form in a bot bubble: labels 12/600, inputs with radius 10, errors in red under their field, a full-width primary
 * "Göndər". Once sent it shows what was sent and "Göndərildi".
 */
@Composable
internal fun FormCardView(
    card: FormCard,
    theme: ClomniTheme,
    modifier: Modifier,
    submit: (Map<String, String>) -> Map<String, String>,
) {
    val values = rememberSaveable(card.messageId, saver = mapSaver()) {
        mutableStateMapOf<String, String>().apply { card.fields.forEach { put(it.id, it.initialValue) } }
    }
    val errors = rememberSaveable(card.messageId, saver = mapSaver()) { mutableStateMapOf<String, String>() }
    var sent by rememberSaveable(card.messageId) { mutableStateOf(false) }
    Column(
        modifier.padding(vertical = ClomniTheme.Space.s.dp, horizontal = ClomniTheme.Space.l.dp),
        verticalArrangement = Arrangement.spacedBy(ClomniTheme.Space.m.dp),
    ) {
        card.text?.let {
            BasicText(
                attributedText(it, theme.colors.primaryText),
                Modifier.clearAndSetSemantics { contentDescription = card.textAccessibilityLabel },
                style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary),
            )
        }
        if (card.readOnly && card.submitted.isNotEmpty()) {
            for (line in card.submitted) {
                Column(Modifier.semantics(mergeDescendants = true) {}) {
                    BasicText(line.label, style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary, FontWeight.SemiBold))
                    BasicText(line.value, Modifier.padding(top = 2.dp), style = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary))
                }
            }
            card.sentLabel?.let { label ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(R.drawable.clomni_ic_check, theme.colors.textSecondary, 14.dp)
                    Spacer(Modifier.width(4.dp))
                    BasicText(label, style = clomniText(ClomniTheme.FontSize.label, theme.colors.textSecondary))
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
                Box(
                    Modifier.fillMaxWidth().heightIn(min = ClomniTheme.Size.touchTarget.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(theme.colors.primary.color.copy(alpha = if (enabled) 1f else 0.6f))
                        .let { box ->
                            if (!enabled) box else box.button(card.submitTitle) {
                                val found = submit(values.toMap())
                                errors.clear()
                                errors.putAll(found)
                                sent = found.isEmpty()
                            }
                        },
                    Alignment.Center,
                ) {
                    BasicText(card.submitTitle, style = clomniText(ClomniTheme.FontSize.text, theme.colors.onPrimary, FontWeight.SemiBold))
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
    val shape = RoundedCornerShape(10.dp)
    val frame = Modifier.fillMaxWidth().heightIn(min = if (field.type == FormFieldType.TEXTAREA) 72.dp else ClomniTheme.Size.touchTarget.dp)
        .clip(shape)
        .background(theme.colors.background.color)
        .border(1.dp, if (error == null) theme.colors.border.color else theme.colors.unread.color, shape)
    val text = clomniText(ClomniTheme.FontSize.text, theme.colors.textPrimary)
    val hint = clomniText(ClomniTheme.FontSize.text, theme.colors.textSecondary)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Read with the field itself ("Ad, soyad, məcburi"), not as a line of its own.
        BasicText(
            if (field.required) "${field.label} *" else field.label,
            Modifier.clearAndSetSemantics {},
            style = clomniText(ClomniTheme.FontSize.label, theme.colors.textPrimary, FontWeight.SemiBold),
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
    FormFieldType.PHONE -> KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next)
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
    Box(modifier.let { if (disabled) it else it.button("$name, ${chosen ?: placeholder.orEmpty()}") { open = true } }) {
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
        modifier.let { if (disabled) it else it.button("$name, ${value.ifEmpty { placeholder.orEmpty() }}") { pick() } }
            .padding(horizontal = ClomniTheme.Space.m.dp),
        Alignment.CenterStart,
    ) {
        BasicText(
            value.ifEmpty { placeholder.orEmpty() },
            style = clomniText(ClomniTheme.FontSize.text, if (value.isEmpty()) theme.colors.textSecondary else theme.colors.textPrimary),
        )
    }
}
