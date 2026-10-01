package ai.clomni.messenger.protocol

/**
 * Parses an RFC 3339 / ISO 8601 date-time (`2026-10-01T10:30:00.000Z`, or with an offset) to epoch milliseconds, and
 * formats one back.
 * Hand-written because java.time needs API 26 (or desugaring in every customer app) and minSdk is 23.
 */
internal object Iso8601 {
    private val pattern =
        Regex("""(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(?:([Zz])|([+-])(\d{2}):(\d{2}))""")

    fun parseMillis(text: String): Long? {
        val groups = pattern.matchEntire(text)?.groupValues ?: return null
        val year = groups[1].toInt()
        val month = groups[2].toInt()
        val day = groups[3].toInt()
        val hour = groups[4].toInt()
        val minute = groups[5].toInt()
        val second = groups[6].toInt()
        val millis = groups[7].take(3).padEnd(3, '0').toInt()
        val offsetHours = if (groups[8].isEmpty()) groups[10].toInt() else 0
        val offsetMinutes = if (groups[8].isEmpty()) groups[11].toInt() else 0
        if (month !in 1..12 || day !in 1..daysInMonth(year, month)) return null
        // 60 is a leap second, which RFC 3339 allows.
        if (hour > 23 || minute > 59 || second > 60 || offsetHours > 23 || offsetMinutes > 59) return null
        val offset = (offsetHours * 60 + offsetMinutes) * (if (groups[9] == "-") -1 else 1)
        val seconds = daysFromCivil(year, month, day) * 86_400 + hour * 3_600 + (minute - offset) * 60 + second
        return seconds * 1_000 + millis
    }

    /** `2026-10-01T10:30:00.000Z`: UTC with milliseconds, the form the server sends. */
    fun format(millis: Long): String {
        val days = millis.floorDiv(86_400_000L)
        val ofDay = millis - days * 86_400_000L
        // Howard Hinnant's civil_from_days.
        val z = days + 719_468
        val era = z.floorDiv(146_097L)
        val dayOfEra = z - era * 146_097
        val yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        val dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        val mp = (5 * dayOfYear + 2) / 153
        val day = dayOfYear - (153 * mp + 2) / 5 + 1
        val month = if (mp < 10) mp + 3 else mp - 9
        val year = yearOfEra + era * 400 + (if (month <= 2) 1 else 0)
        fun pad(value: Long, width: Int) = value.toString().padStart(width, '0')
        return "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}T${pad(ofDay / 3_600_000, 2)}:" +
            "${pad(ofDay / 60_000 % 60, 2)}:${pad(ofDay / 1_000 % 60, 2)}.${pad(ofDay % 1_000, 3)}Z"
    }

    private fun daysInMonth(year: Int, month: Int): Int = when (month) {
        2 -> if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) 29 else 28
        4, 6, 9, 11 -> 30
        else -> 31
    }

    // Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's days_from_civil).
    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        val y = (if (month <= 2) year - 1 else year).toLong()
        val era = y.floorDiv(400L)
        val yearOfEra = y - era * 400
        val dayOfYear = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
        val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
