package ai.clomni.messenger.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.OffsetDateTime

class Iso8601Test {

    @Test
    fun matchesJavaTime() {
        val times = listOf(
            "2026-10-01T10:30:00Z",
            "2026-10-01T10:30:00.000Z",
            "2026-10-01T10:30:00.5Z",
            "2026-10-01T10:30:00.123456789Z",
            "2026-10-01T14:30:00+04:00",
            "2026-10-01T06:30:00-04:00",
            "2026-03-01T01:00:00+05:30",
            "2024-02-29T23:59:59.999Z",
            "2000-02-29T00:00:00Z",
            "1970-01-01T00:00:00Z",
            "1969-12-31T23:59:59Z",
            "0001-01-01T00:00:00Z",
            "0000-02-28T12:00:00Z",
            "9999-12-31T23:59:59Z",
        )
        for (time in times) {
            assertEquals(time, OffsetDateTime.parse(time).toInstant().toEpochMilli(), Iso8601.parseMillis(time))
        }
    }

    @Test
    fun lowerCaseSeparatorsAndLeapSecond() {
        val expected = OffsetDateTime.parse("2026-10-01T10:30:00Z").toInstant().toEpochMilli()
        assertEquals(expected, Iso8601.parseMillis("2026-10-01t10:30:00z"))
        assertEquals(
            OffsetDateTime.parse("2017-01-01T00:00:00Z").toInstant().toEpochMilli(),
            Iso8601.parseMillis("2016-12-31T23:59:60Z"),
        )
    }

    @Test
    fun rejectsWhatIsNotADateTime() {
        val invalid = listOf(
            "",
            "2026-10-01",
            "2026-10-01T10:30:00",
            "2026-10-01 10:30:00Z",
            "2026-13-01T00:00:00Z",
            "2026-00-01T00:00:00Z",
            "2026-02-29T00:00:00Z",
            "1900-02-29T00:00:00Z",
            "2026-04-31T00:00:00Z",
            "2026-10-00T00:00:00Z",
            "2026-10-01T24:00:00Z",
            "2026-10-01T10:60:00Z",
            "2026-10-01T10:30:61Z",
            "2026-10-01T10:30:00+24:00",
            "2026-10-01T10:30:00+04:60",
            "2026-10-01T10:30:00.Z",
            " 2026-10-01T10:30:00Z",
        )
        for (text in invalid) assertNull(text, Iso8601.parseMillis(text))
    }
}
