package ai.clomni.messenger.presentation

import java.net.URI
import java.util.Locale

/**
 * A piece of message text with one style. [link] is only ever an https:, tel: or mailto: address, or an http: one the
 * message wrote out in full.
 */
internal data class TextRun(
    val text: String,
    val bold: Boolean = false,
    val italic: Boolean = false,
    val link: String? = null,
)

/**
 * The markdown messages may carry (brief 8·3): **bold**, *italic*, [text](url), line breaks and emoji. A link with any
 * other scheme (javascript:, http:, data:…) keeps its text and loses the link. A marker without its pair, or with a
 * space on its inner side ("2 * 3 * 4"), is plain text. Addresses written out in the text become links too ([linked]).
 * The same rules as the iOS SDK.
 */
internal object LimitedMarkdown {
    val linkSchemes = setOf("https", "tel", "mailto")

    fun parse(source: String): List<TextRun> {
        val runs = mutableListOf<TextRun>()
        parse(source, bold = false, italic = false, runs)
        return merged(runs)
    }

    /** The text as TalkBack and previews read it. */
    fun plainText(source: String): String = parse(source).joinToString("") { it.text }

    /** [target] when it is a link a message may open, otherwise null. */
    fun safeLink(target: String): String? {
        val scheme = runCatching { URI(target).scheme }.getOrNull()?.lowercase(Locale.ROOT) ?: return null
        return target.takeIf { scheme in linkSchemes }
    }

    /**
     * Plain text with the addresses in it made links: https:// and http:// as written, www. over https, an e-mail
     * (mailto:) and a phone number, +994… or nine digits and more (tel:). A full stop, comma or unpaired bracket after
     * an address stays text.
     */
    fun linked(text: String, bold: Boolean = false, italic: Boolean = false): List<TextRun> {
        val runs = mutableListOf<TextRun>()
        var index = 0
        while (index < text.length) {
            // The earliest; at one place a web address before an e-mail before a phone number.
            val found = listOfNotNull(web(text, index), email(text, index), phone(text, index)).minByOrNull { it.start } ?: break
            if (found.start > index) runs += TextRun(text.substring(index, found.start), bold, italic)
            runs += TextRun(text.substring(found.start, found.end), bold, italic, found.target)
            index = found.end
        }
        if (index < text.length) runs += TextRun(text.substring(index), bold, italic)
        return runs
    }

    private class Address(val start: Int, val end: Int, val target: String)

    private val WEB = Regex("""(?<![\p{L}\p{N}@./_-])(?:https?://|www\.)[^\s<>"]+""", RegexOption.IGNORE_CASE)
    private val EMAIL = Regex("""(?<![\p{L}\p{N}._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(?![\p{L}\p{N}-])""")

    /**
     * +994 50 123 45 67, (050) 123-45-67, 0501234567: spaces, hyphens and brackets only after a + or a leading 0 and a
     * code, so a date or a sum ("2026-10-07 11:00", "1 000 000 000") stays text; otherwise nine digits in a row.
     */
    private val PHONE = Regex(
        """(?<![\p{L}\p{N}+@/._-])(?:(?:\+|\((?=0[1-9])|(?=0[1-9]))\d+(?:(?:[ -]|\) ?|[ -]?\()\d+)*|\d{9,})(?![\p{L}\p{N}])""",
    )

    private fun web(text: String, from: Int): Address? {
        var match = WEB.find(text, from)
        while (match != null) {
            var end = match.range.last + 1
            while (end > match.range.first && unpaired(text, match.range.first, end)) end--
            val found = text.substring(match.range.first, end)
            val target = if (found.startsWith("www.", ignoreCase = true)) "https://$found" else found
            // A host with a dot in it: "https://x" is not an address yet.
            val host = found.substringAfter("://").substringBefore('/').substringBefore('?').substringBefore('#')
            if (host.trimEnd('.').contains('.')) return Address(match.range.first, end, target)
            match = match.next()
        }
        return null
    }

    /** The last character of text[start, end) is punctuation after the address, not part of it. */
    private fun unpaired(text: String, start: Int, end: Int): Boolean {
        val last = text[end - 1]
        if (last in ".,;:!?'*") return true
        val open = when (last) {
            ')' -> '('
            ']' -> '['
            '}' -> '{'
            else -> return false
        }
        val part = text.subSequence(start, end)
        return part.count { it == open } < part.count { it == last }
    }

    private fun email(text: String, from: Int): Address? =
        EMAIL.find(text, from)?.let { Address(it.range.first, it.range.last + 1, "mailto:${it.value}") }

    private fun phone(text: String, from: Int): Address? {
        var match = PHONE.find(text, from)
        while (match != null) {
            val number = match.value.filter { it.isDigit() || it == '+' }
            if (number.count(Char::isDigit) in 9..15) return Address(match.range.first, match.range.last + 1, "tel:$number")
            match = match.next()
        }
        return null
    }

    private fun parse(chars: String, bold: Boolean, italic: Boolean, runs: MutableList<TextRun>) {
        val buffer = StringBuilder()
        fun flush() {
            if (buffer.isNotEmpty()) runs += linked(buffer.toString(), bold, italic)
            buffer.setLength(0)
        }
        var index = 0
        while (index < chars.length) {
            val boldEnd = if (!bold) closing("**", chars, index) else null
            if (boldEnd != null) {
                flush()
                parse(chars.substring(index + 2, boldEnd), true, italic, runs)
                index = boldEnd + 2
                continue
            }
            val single = chars[index] == '*' && !(index + 1 < chars.length && chars[index + 1] == '*')
            val italicEnd = if (!italic && single) closing("*", chars, index) else null
            if (italicEnd != null) {
                flush()
                parse(chars.substring(index + 1, italicEnd), bold, true, runs)
                index = italicEnd + 1
                continue
            }
            val link = if (chars[index] == '[') link(chars, index) else null
            if (link != null) {
                flush()
                runs += TextRun(link.label, bold, italic, safeLink(link.target))
                index = link.end
                continue
            }
            buffer.append(chars[index])
            index++
        }
        flush()
    }

    /**
     * Where the [marker] opened at [start] closes: the same marker later on, with text between that neither starts nor
     * ends with a space.
     */
    private fun closing(marker: String, chars: String, start: Int): Int? {
        val width = marker.length
        if (start + width >= chars.length || !chars.regionMatches(start, marker, 0, width)) return null
        if (chars[start + width].isWhitespace()) return null
        var index = start + width + 1
        while (index + width <= chars.length) {
            // Inside *italic*, a ** is bold, not the end.
            if (width == 1 && chars[index] == '*' && index + 1 < chars.length && chars[index + 1] == '*') {
                index += 2
                continue
            }
            if (chars.regionMatches(index, marker, 0, width) && !chars[index - 1].isWhitespace()) return index
            index++
        }
        return null
    }

    private class Link(val label: String, val target: String, val end: Int)

    /** `[label](target)` starting at [start], with balanced parentheses in the target, on one line. */
    private fun link(chars: String, start: Int): Link? {
        val labelEnd = chars.indexOf(']', start + 1)
        if (labelEnd < 0 || labelEnd + 1 >= chars.length || chars[labelEnd + 1] != '(') return null
        var depth = 0
        var index = labelEnd + 1
        while (index < chars.length) {
            when (chars[index]) {
                '(' -> depth++
                ')' -> {
                    depth--
                    if (depth == 0) {
                        val label = chars.substring(start + 1, labelEnd)
                        val target = chars.substring(labelEnd + 2, index).trim()
                        return if (label.isEmpty()) null else Link(label, target, index + 1)
                    }
                }
                '\n' -> return null
            }
            index++
        }
        return null
    }

    private fun merged(runs: List<TextRun>): List<TextRun> {
        val result = mutableListOf<TextRun>()
        for (run in runs) {
            val last = result.lastOrNull()
            if (last != null && last.bold == run.bold && last.italic == run.italic && last.link == null && run.link == null) {
                result[result.size - 1] = TextRun(last.text + run.text, run.bold, run.italic)
            } else {
                result += run
            }
        }
        return result
    }
}
