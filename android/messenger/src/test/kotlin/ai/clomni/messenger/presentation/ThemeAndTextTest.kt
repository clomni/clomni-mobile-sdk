package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone
import kotlin.math.abs

class ThemeTest {
    private val apar = RgbColor.parse("#1F9D63")!!

    /** Each channel of [actual] within [tolerance] (of 255) of the brief's example. */
    private fun assertClose(actual: RgbColor, expected: String, tolerance: Double) {
        val target = RgbColor.parse(expected)!!
        val worst = listOf(actual.red - target.red, actual.green - target.green, actual.blue - target.blue).maxOf { abs(it) * 255 }
        assertTrue("$actual vs $expected", worst <= tolerance)
    }

    private fun brand(color: String, onPrimary: String? = null): MessengerConfig.Brand {
        val on = onPrimary?.let { ""","on_primary_color":"$it"""" }.orEmpty()
        return ProtocolJson().parseConfig("""{"brand":{"name":"Apar","primary_color":"$color"$on}}""")!!.brand
    }

    @Test
    fun hexAndArithmetic() {
        assertEquals("#1F9D63", apar.hex)
        assertEquals("#1F9D63", apar.toString())
        assertEquals(0xFF1F9D63.toInt(), apar.argb)
        for (bad in listOf("1F9D63", "#1F9D6", "#1F9D6Z", "#1F9D6300", "#+1F9D6")) assertNull(bad, RgbColor.parse(bad))
        assertEquals("channels are clamped", "#FF0080", RgbColor(2.0, -1.0, 0.5).hex)
        assertEquals(21.0, RgbColor.WHITE.contrast(RgbColor.BLACK), 0.001)
        assertEquals(1.0, apar.contrast(apar), 0.001)
        assertEquals(3.46, apar.contrast(RgbColor.WHITE), 0.01)
        assertEquals("#808080", RgbColor.BLACK.over(RgbColor.WHITE, 0.5).hex)
        for (hex in listOf("#1F9D63", "#E5484D", "#0A66C2", "#FFFFFF", "#000000", "#808080", "#FF00FF", "#FFFF00", "#00FFFF")) {
            val (hue, saturation, lightness) = RgbColor.parse(hex)!!.hsl
            assertEquals("HSL round trip", hex, RgbColor.fromHsl(hue, saturation, lightness).hex)
        }
        assertEquals("hue wraps", "#0000FF", RgbColor.fromHsl(-120.0, 1.0, 0.5).hex)
        assertEquals("lightness stops at white", "#FFFFFF", apar.steps(20).hex)
        assertEquals(apar, RgbColor.parse("#1f9d63"))
        assertEquals(apar.hashCode(), RgbColor.parse("#1F9D63").hashCode())
        assertFalse(apar.equals("#1F9D63"))
    }

    /** Brief 8·7.1 with #1F9D63: primaryDark #13734A, primarySoft #BFE3CF, dark primarySoft #2F5E46, primary +1 step. */
    @Test
    fun derivedColoursMatchTheBriefsExamples() {
        val light = ClomniTheme.make(brand("#1F9D63"), dark = false).colors
        assertEquals(apar, light.primary)
        assertClose(light.primaryDark, "#13734A", 5.0)
        assertClose(light.primarySoft, "#BFE3CF", 10.0)

        val dark = ClomniTheme.make(brand("#1F9D63"), dark = true).colors
        assertClose(dark.primarySoft, "#2F5E46", 5.0)
        val reference = RgbColor.parse("#34B57A")!!.hsl
        assertEquals(reference.hue, dark.primary.hsl.hue, 1.0)
        assertEquals(reference.lightness, dark.primary.hsl.lightness, 0.015)
        assertEquals("#27C87E", dark.primary.hex)
        assertEquals("the header's darker tone is the brand colour itself in dark mode", apar.hex, dark.primaryDark.hex)
    }

    @Test
    fun neutralTokens() {
        val light = ClomniTheme.make(null, dark = false)
        assertFalse(light.isDark)
        assertEquals(
            listOf("#FFFFFF", "#F5F6F8", "#F1F2F4", "#1B1D21", "#707480", "#E7E8EB", "#E5484D", "#FFF4CC", "#5C4400"),
            light.colors.run { listOf(background, canvas, surface, textPrimary, textSecondary, border, unread, warning, onWarning) }.map { it.hex },
        )
        val dark = ClomniTheme.make(null, dark = true)
        assertTrue(dark.isDark)
        assertEquals(
            listOf("#121316", "#0B0C0E", "#22242A", "#F2F3F5", "#9A9DA6", "#2A2C32", "#E5484D", "#3D3415", "#F2DC8B"),
            dark.colors.run { listOf(background, canvas, surface, textPrimary, textSecondary, border, unread, warning, onWarning) }.map { it.hex },
        )
        assertEquals("Clomni's colour without a config", "#10A670", light.colors.primary.hex)
        for (theme in listOf(light, dark)) {
            assertTrue(theme.colors.warning.contrast(theme.colors.onWarning) >= 4.5)
            assertTrue(theme.colors.background.contrast(theme.colors.textPrimary) >= 4.5)
            // #707480 instead of the brief's #737780 (4.49:1): secondary text reaches AA on the background too.
            assertTrue(theme.colors.background.contrast(theme.colors.textSecondary) >= 4.5)
        }
        assertEquals(12f, ClomniTheme.Radius.card)
        assertEquals(40f, ClomniTheme.Size.cardOverlap)
        assertEquals(48f, ClomniTheme.Size.touchTarget)
        assertEquals(listOf(2.0, 10.0), ClomniTheme.Shadow.card.map { it.radius })
    }

    /** onPrimary: the config's colour, otherwise white or black by WCAG 4.5:1. */
    @Test
    fun textOnPrimary() {
        assertEquals(RgbColor.WHITE, ClomniTheme.make(brand("#1F9D63", onPrimary = "#FFFFFF"), dark = false).colors.onPrimary)
        // White on #1F9D63 is 3.5:1, black 6.1:1.
        assertEquals(RgbColor.BLACK, ClomniTheme.make(brand("#1F9D63"), dark = false).colors.onPrimary)
        assertEquals(RgbColor.WHITE, ClomniTheme.make(brand("#1A2B4C"), dark = false).colors.onPrimary)
        assertEquals(RgbColor.BLACK, ClomniTheme.make(brand("#FFD60A"), dark = false).colors.onPrimary)
        val greys = (0..255).map { RgbColor(it / 255.0, it / 255.0, it / 255.0) }
        val brands = listOf("#1F9D63", "#10A670", "#0A66C2", "#E5484D", "#FFD60A", "#5A2D82").mapNotNull(RgbColor::parse)
        for (background in greys + brands) {
            assertTrue("$background", background.contrast(ClomniTheme.readableText(background)) >= 4.5)
        }
    }

    @Test
    fun appearance() {
        assertTrue(ClomniTheme.isDark(MessengerConfig.Theme.DARK, systemIsDark = false))
        assertFalse(ClomniTheme.isDark(MessengerConfig.Theme.LIGHT, systemIsDark = true))
        assertTrue(ClomniTheme.isDark(MessengerConfig.Theme.SYSTEM, systemIsDark = true))
        assertFalse(ClomniTheme.isDark(null, systemIsDark = false))
    }
}

class StringsTest {
    @Test
    fun everyKeyHasAzEnAndRu() {
        for (language in listOf("az", "en", "ru")) {
            val strings = ClomniStrings(language)
            for (key in Key.entries) {
                assertNotNull("$language has no $key", ClomniStrings.FALLBACKS.getValue(language)[key])
                assertFalse("plain punctuation only: ${strings[key]}", strings[key].contains("—"))
            }
            assertEquals(12, strings.months.size)
        }
    }

    @Test
    fun languageAndOverrides() {
        assertEquals("Messages", ClomniStrings("en")[Key.TAB_MESSAGES])
        assertEquals("Главная", ClomniStrings("ru-RU")[Key.TAB_HOME])
        assertEquals("anything else reads as az", "Ana səhifə", ClomniStrings("de")[Key.TAB_HOME])
        assertEquals("az", ClomniStrings(null).language)
        // The panel's texts come first; an empty one does not hide the SDK's.
        val strings = ClomniStrings("az", mapOf("yesterday" to "Dün", "send" to "", "custom" to "x"))
        assertEquals("Dün", strings[Key.YESTERDAY])
        assertEquals("Göndər", strings[Key.SEND])
        assertEquals("2 dəq", strings.format(Key.MINUTES_SHORT, 2))
        assertEquals("İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq", ClomniStrings("az")[Key.OFFLINE])
    }
}

class TimeTextTest {
    private val baku = TimeZone.getTimeZone("Asia/Baku")

    /** 2026-10-01 10:30 in Baku. */
    private val now = 1_790_836_200_000L

    private fun text(language: String) = TimeText(ClomniStrings(language), baku)

    private fun ago(seconds: Long) = now - seconds * 1_000

    @Test
    fun ago() {
        val az = text("az")
        assertEquals("indi", az.ago(ago(30), now))
        assertEquals("a clock running ahead is now", "indi", az.ago(ago(-120), now))
        assertEquals("2 dəq", az.ago(ago(130), now))
        assertEquals("3 saat", az.ago(ago(3 * 3_600 + 5), now))
        assertEquals("2 gün", az.ago(ago(2 * 86_400), now))
        assertEquals("21 sentyabr", az.ago(ago(10 * 86_400), now))
        assertEquals("5 dekabr 2025", az.ago(ago(300 * 86_400), now))
        assertEquals("2 min", text("en").ago(ago(130), now))
        assertEquals("December 5, 2025", text("en").ago(ago(300 * 86_400), now))
        assertEquals("21 сентября", text("ru").ago(ago(10 * 86_400), now))
        assertEquals("1 мин", text("ru").ago(ago(60), now))
    }

    @Test
    fun day() {
        val az = text("az")
        assertEquals("Bu gün 10:30", az.day(now, now))
        assertEquals("Bu gün 00:05", az.day(ago(10 * 3_600 + 25 * 60), now))
        assertEquals("Dünən 23:30", az.day(ago(11 * 3_600), now))
        assertEquals("28 sentyabr 10:30", az.day(ago(3 * 86_400), now))
        assertEquals("5 dekabr 2025 10:30", az.day(ago(300 * 86_400), now))
        assertEquals("Today 10:30", text("en").day(now, now))
        assertEquals("September 28, 10:30", text("en").day(ago(3 * 86_400), now))
        assertEquals("Вчера 23:30", text("ru").day(ago(11 * 3_600), now))
        // The panel's "Dün" replaces the SDK's "Dünən".
        assertEquals("Dün 23:30", TimeText(ClomniStrings("az", mapOf("yesterday" to "Dün")), baku).day(ago(11 * 3_600), now))
        assertEquals("the device's time zone", "06:30", TimeText(ClomniStrings("az"), TimeZone.getTimeZone("UTC")).clock(now))
    }

    /** When the team is back: "09:00" today, "sabah 09:00" tomorrow, the date after that. */
    @Test
    fun upcoming() {
        val az = text("az")
        val hour = 3_600L
        assertEquals("23:30", az.upcoming(now + 13 * hour * 1_000, now))
        assertEquals("sabah 09:00", az.upcoming(now + (22 * hour + 1_800) * 1_000, now))
        assertEquals("tomorrow 09:00", text("en").upcoming(now + (22 * hour + 1_800) * 1_000, now))
        assertEquals("завтра 09:00", text("ru").upcoming(now + (22 * hour + 1_800) * 1_000, now))
        assertEquals("3 oktyabr 09:00", az.upcoming(now + (46 * hour + 1_800) * 1_000, now))
        assertEquals("October 3, 09:00", text("en").upcoming(now + (46 * hour + 1_800) * 1_000, now))
        assertEquals("4 yanvar 2027 09:00", az.upcoming(now + (94 * 24 * hour + 22 * hour + 1_800) * 1_000, now))
    }
}
