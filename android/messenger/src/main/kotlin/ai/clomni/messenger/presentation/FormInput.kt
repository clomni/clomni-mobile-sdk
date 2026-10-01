package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessageContent.FormFieldType
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * What a form's fields hold while the user fills them in, checked here before anything is sent (the server checks
 * again; its `validation_failed` fields land in the same place). The same rules as the iOS SDK.
 */
internal object FormInput {
    /** Field key → error text; empty when the form can be sent. */
    fun errors(form: MessageContent.Form, values: Map<String, String>, strings: ClomniStrings): Map<String, String> {
        val errors = LinkedHashMap<String, String>()
        for (field in form.fields) {
            val value = values[field.key].orEmpty().trim()
            if (value.isEmpty()) {
                if (field.required) {
                    errors[field.key] = strings[if (field.type == FormFieldType.SELECT) Key.CHOOSE_OPTION else Key.FIELD_REQUIRED]
                }
                continue
            }
            val limit = field.maxLength
            if (limit != null && value.codePointCount(0, value.length) > limit) {
                errors[field.key] = strings.format(Key.TOO_LONG, limit)
                continue
            }
            val error = when (field.type) {
                FormFieldType.EMAIL -> Key.INVALID_EMAIL.takeIf { !isEmail(value) }
                FormFieldType.PHONE -> Key.INVALID_PHONE.takeIf { phone(value, field.defaultCountry) == null }
                FormFieldType.NUMBER -> Key.INVALID_NUMBER.takeIf { number(value) == null }
                FormFieldType.SELECT -> Key.CHOOSE_OPTION.takeIf { field.options.none { it.value == value } }
                FormFieldType.DATE -> Key.FIELD_REQUIRED.takeIf { !isDate(value) }
                else -> null
            }
            if (error != null) errors[field.key] = strings[error]
        }
        return errors
    }

    /**
     * The `values` of a form_submit: every field, numbers as numbers, phones in international form, an empty optional
     * field as "".
     */
    fun payload(form: MessageContent.Form, values: Map<String, String>): Map<String, JsonElement> =
        form.fields.associate { field ->
            val value = values[field.key].orEmpty().trim()
            field.key to when (field.type) {
                FormFieldType.NUMBER -> number(value)?.let(::numberJson) ?: JsonPrimitive(value)
                FormFieldType.PHONE -> JsonPrimitive(phone(value, field.defaultCountry) ?: value)
                else -> JsonPrimitive(value)
            }
        }

    /** What the logged-in user's known details fill in before they type: name, email, phone by key or type. */
    fun prefill(form: MessageContent.Form, known: Map<String, String>): Map<String, String> {
        val values = LinkedHashMap<String, String>()
        for (field in form.fields) {
            val byType = when (field.type) {
                FormFieldType.EMAIL -> known["email"]
                FormFieldType.PHONE -> known["phone"]
                else -> null
            }
            val value = known[field.key] ?: byType
            if (!value.isNullOrEmpty()) values[field.key] = value
        }
        return values
    }

    /** A submitted form as label · value lines, in the form's order. */
    fun submittedLines(form: MessageContent.Form): List<Pair<String, String>> {
        val submitted = form.submitted ?: return emptyList()
        return form.fields.mapNotNull { field ->
            val value = submitted[field.key] as? JsonPrimitive ?: return@mapNotNull null
            val text = when {
                value is JsonNull -> ""
                value.isString -> field.options.firstOrNull { it.value == value.content }?.label ?: value.content
                value.booleanOrNull != null -> if (value.booleanOrNull == true) "✓" else "–"
                else -> value.longOrNull?.toString() ?: value.doubleOrNull?.let(::numberText) ?: ""
            }
            if (text.isEmpty()) null else field.label to text
        }
    }

    /**
     * "+994501234567" from "+994 50 123 45 67", "050 123 45 67" or "501234567" with default country AZ; null when it
     * cannot be a phone number.
     */
    fun phone(raw: String, defaultCountry: String?): String? {
        val international = raw.trim().startsWith("+")
        if (raw.any { it !in PHONE_CHARACTERS }) return null
        var digits = raw.filter { it in '0'..'9' }
        if (!international) {
            val code = defaultCountry?.let { CALLING_CODES[it.uppercase()] }
            digits = when {
                digits.startsWith("00") -> digits.drop(2)
                code != null -> code + digits.trimStart('0')
                else -> return null
            }
        }
        return if (digits.length in 8..15) "+$digits" else null
    }

    /** "2,5" too; a plain decimal, nothing Kotlin's parser would add (hex, "2f"). */
    fun number(raw: String): Double? {
        val text = raw.replace(',', '.')
        if (!DECIMAL.matches(text)) return null
        return text.toDoubleOrNull()?.takeIf { it.isFinite() }
    }

    fun isEmail(value: String): Boolean = EMAIL.matches(value)

    /** The date picker's "yyyy-MM-dd". */
    fun isDate(value: String): Boolean = DATE.matches(value)

    private fun numberJson(number: Double): JsonPrimitive =
        if (number == Math.floor(number) && Math.abs(number) < 1e15) JsonPrimitive(number.toLong()) else JsonPrimitive(number)

    private fun numberText(number: Double): String =
        if (number == Math.floor(number) && Math.abs(number) < 1e15) number.toLong().toString() else number.toString()

    private const val PHONE_CHARACTERS = "0123456789+ -()."
    private val DECIMAL = Regex("""[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?""")
    private val EMAIL = Regex("""[^@\s]+@[^@\s]+\.[^@\s]+""")
    private val DATE = Regex("""\d{4}-\d{2}-\d{2}""")

    /** The countries the panel offers as a phone field's `default_country`. */
    val CALLING_CODES = mapOf(
        "AZ" to "994", "TR" to "90", "RU" to "7", "KZ" to "7", "GE" to "995", "UA" to "380", "UZ" to "998",
        "BY" to "375", "KG" to "996", "TJ" to "992", "TM" to "993", "AM" to "374", "IR" to "98", "AE" to "971",
        "SA" to "966", "QA" to "974", "IL" to "972", "US" to "1", "CA" to "1", "GB" to "44", "DE" to "49", "FR" to "33",
        "IT" to "39", "ES" to "34", "NL" to "31", "PL" to "48", "CN" to "86", "IN" to "91",
    )
}
