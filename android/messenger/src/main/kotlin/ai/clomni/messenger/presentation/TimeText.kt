package ai.clomni.messenger.presentation

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** Times as the messenger writes them, in the device's time zone, with the SDK's own month names and 24 hours. */
internal class TimeText(private val strings: ClomniStrings, private val timeZone: TimeZone = TimeZone.getDefault()) {

    /** How long ago, for lists and the Home card: "indi", "2 dəq", "3 saat", "4 gün", then the date ("1 oktyabr"). */
    fun ago(date: Long, now: Long): String {
        val seconds = (now - date) / 1_000
        return when {
            seconds < 60 -> strings[ClomniStrings.Key.NOW]
            seconds < 3_600 -> strings.format(ClomniStrings.Key.MINUTES_SHORT, (seconds / 60).toInt())
            seconds < 86_400 -> strings.format(ClomniStrings.Key.HOURS_SHORT, (seconds / 3_600).toInt())
            seconds < 604_800 -> strings.format(ClomniStrings.Key.DAYS_SHORT, (seconds / 86_400).toInt())
            else -> dayAndMonth(date, withYear = !sameYear(date, now))
        }
    }

    /** Under the last bubble of a run: "indi" within a minute, then the clock ("12:42"). */
    fun stamp(date: Long, now: Long): String =
        if (now - date < 60_000) strings[ClomniStrings.Key.NOW] else clock(date)

    /**
     * For the conversation's time separators: "Bu gün 10:30", "Dünən 10:30", "1 oktyabr 10:30", and with the year
     * when it is not this one.
     */
    fun day(date: Long, now: Long): String {
        val time = clock(date)
        val day = calendar(date)
        val today = calendar(now)
        if (sameDay(day, today)) return "${strings[ClomniStrings.Key.TODAY]} $time"
        today.add(Calendar.DAY_OF_MONTH, -1)
        if (sameDay(day, today)) return "${strings[ClomniStrings.Key.YESTERDAY]} $time"
        val separator = if (strings.language == "en") ", " else " "
        return dayAndMonth(date, withYear = !sameYear(date, now)) + separator + time
    }

    /**
     * A time to come, for "Növbəti iş saatı: …": "09:00" today, "sabah 09:00" tomorrow, "2 oktyabr 09:00" after that
     * (with the year when it is not this one).
     */
    fun upcoming(date: Long, now: Long): String {
        val time = clock(date)
        val day = calendar(date)
        val next = calendar(now)
        if (sameDay(day, next)) return time
        next.add(Calendar.DAY_OF_MONTH, 1)
        if (sameDay(day, next)) return "${strings[ClomniStrings.Key.TOMORROW]} $time"
        val separator = if (strings.language == "en") ", " else " "
        return dayAndMonth(date, withYear = !sameYear(date, now)) + separator + time
    }

    /** 24-hour "10:30". */
    fun clock(date: Long): String {
        val calendar = calendar(date)
        val hour = calendar.get(Calendar.HOUR_OF_DAY)
        return String.format(Locale.ROOT, "%02d:%02d", hour, calendar.get(Calendar.MINUTE))
    }

    private fun dayAndMonth(date: Long, withYear: Boolean): String {
        val calendar = calendar(date)
        val month = strings.months[calendar.get(Calendar.MONTH)]
        val day = calendar.get(Calendar.DAY_OF_MONTH)
        val year = calendar.get(Calendar.YEAR).takeIf { withYear }
        return if (strings.language == "en") {
            "$month $day" + (year?.let { ", $it" } ?: "")
        } else {
            "$day $month" + (year?.let { " $it" } ?: "")
        }
    }

    private fun sameYear(a: Long, b: Long) = calendar(a).get(Calendar.YEAR) == calendar(b).get(Calendar.YEAR)

    private fun sameDay(a: Calendar, b: Calendar) =
        a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

    private fun calendar(millis: Long): Calendar =
        Calendar.getInstance(timeZone, Locale.ROOT).apply { timeInMillis = millis }
}
