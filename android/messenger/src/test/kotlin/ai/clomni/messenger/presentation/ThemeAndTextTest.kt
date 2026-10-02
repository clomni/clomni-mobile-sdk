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

class ThemeTest {
    private val apar = RgbColor.parse("#1F9D63")!!

    private fun brand(color: String, style: String = "gradient"): MessengerConfig.Brand =
        ProtocolJson().parseConfig("""{"brand":{"name":"Apar","primary_color":"$color","header_style":"$style"}}""")!!.brand

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

    /** APPEARANCE-CONTRACT 1: the server's colours, light and dark, as sent. */
    @Test
    fun theServersColoursAreUsed() {
        val brand = Fixture.aparConfig.brand
        val light = ClomniTheme.make(brand, dark = false).colors
        assertEquals(
            listOf("#1F9D63", "#000000", "#E9F5EF", "#CEE9DD", "#1F9D63", "#177248", "#FFFFFF"),
            light.run { listOf(primary, onPrimary, primarySoft, primaryLine, headerFrom, headerTo, headerText) }.map { it.hex },
        )
        val dark = ClomniTheme.make(brand, dark = true).colors
        assertEquals(
            listOf("#27C87E", "#000000", "#142520", "#173B2D", "#1F9D63", "#0E482D", "#FFFFFF"),
            dark.run { listOf(primary, onPrimary, primarySoft, primaryLine, headerFrom, headerTo, headerText) }.map { it.hex },
        )
    }

    /**
     * header_text (APPEARANCE-CONTRACT 1): white where white reaches 3:1 on both of the header's colours, otherwise
     * #1B1D21; white on a picture, which has its veil. on_primary is never the header's.
     */
    @Test
    fun headerText() {
        // Apar's green keeps the brief's white text: 3.46:1 at the top, more below.
        val derived = ClomniTheme.make(brand("#1F9D63"), dark = false).colors
        assertEquals("#1F9D63", derived.headerFrom.hex)
        assertEquals("#FFFFFF", derived.headerText.hex)
        // A light green is too light for it: white is 2.18:1 on #27C87E.
        val light = ClomniTheme.make(brand("#27C87E"), dark = false).colors
        assertEquals(2.18, light.headerFrom.contrast(RgbColor.WHITE), 0.01)
        assertEquals("#1B1D21", light.headerText.hex)
        assertEquals("#FFFFFF", ClomniTheme.make(brand("#1F9D63"), dark = true).colors.headerText.hex)
        assertEquals("#FFFFFF", ClomniTheme.make(brand("#0A66C2"), dark = false).colors.headerText.hex)
        assertEquals("#1B1D21", ClomniTheme.make(brand("#FFD400", style = "solid"), dark = false).colors.headerText.hex)
        // In dark mode on_primary is near-black, which a dark header would swallow; the header's text stays white.
        val blue = ClomniTheme.make(brand("#0A66C2"), dark = true).colors
        assertEquals(listOf("#000000", "#FFFFFF"), listOf(blue.onPrimary.hex, blue.headerText.hex))
        val picture = ProtocolJson()
            .parseConfig("""{"brand":{"primary_color":"#FFD400","header_style":"image","header_image_url":"https://x/h.png"}}""")!!
        assertEquals("#FFFFFF", ClomniTheme.make(picture.brand, dark = false).colors.headerText.hex)
        val noText = Fixture.aparConfig.brand.let { b ->
            b.copy(colors = b.colors!!.copy(light = b.colors!!.light.copy(headerFrom = "#3FB37C", headerText = null)))
        }
        assertEquals("from the server's #3FB37C", "#1B1D21", ClomniTheme.make(noText, dark = false).colors.headerText.hex)
    }

    /** config.changed and setTheme: the screen's colours move to the new ones rather than jump. */
    @Test
    fun aNewLookFadesIn() {
        val from = ClomniTheme.make(brand("#1F9D63"), dark = false)
        val to = ClomniTheme.make(brand("#0A66C2"), dark = true)
        assertEquals(from.colors, from.toward(to, 0.0).colors)
        assertEquals(to, from.toward(to, 1.0))
        val half = from.toward(to, 0.5)
        assertEquals(to.colors.primary.over(from.colors.primary, 0.5), half.colors.primary)
        assertEquals(to.colors.background.over(from.colors.background, 0.5), half.colors.background)
        assertTrue(half.isDark)
        assertEquals(to, to.toward(to, 0.3))
    }

    /**
     * Without the server's colours the SDK derives them by the same rules, and to the same values as the server's
     * (the contract's example, computed by AppSdk::Colors): soft 10% and line 22% over the background, the header from
     * the brand to one step darker (dark: two steps).
     */
    @Test
    fun derivedColoursAreTheServers() {
        val server = Fixture.aparConfig.brand
        for (dark in listOf(false, true)) {
            // Compared as #RRGGBB: the server sends 8-bit channels.
            assertEquals(ClomniTheme.make(server, dark).toString(), ClomniTheme.make(server.copy(colors = null), dark).toString())
        }
        val light = ClomniTheme.make(brand("#1F9D63"), dark = false).colors
        assertEquals(apar, light.primary)
        assertEquals(apar, light.headerFrom)
        assertEquals(apar.steps(-1), light.headerTo)

        val dark = ClomniTheme.make(brand("#1F9D63"), dark = true).colors
        assertEquals(apar.steps(1), dark.primary)
        assertEquals("the header's top is the brand colour itself in dark mode", apar.hex, dark.headerFrom.hex)
        assertEquals(apar.steps(-2), dark.headerTo)
        val night = RgbColor.parse("#121316")!!
        assertEquals(dark.primary.over(night, 0.10), dark.primarySoft)
        assertEquals(dark.primary.over(night, 0.22), dark.primaryLine)

        val solid = ClomniTheme.make(brand("#1F9D63", style = "solid"), dark = false).colors
        assertEquals(listOf(apar, apar), listOf(solid.headerFrom, solid.headerTo))
    }

    /** Clomni.setTheme: the app's colour (derived here) and mode win over the panel's. */
    @Test
    fun theAppsThemeWins() {
        val override = ThemeOverride(RgbColor.parse("#0A66C2"), MessengerConfig.ThemeMode.DARK)
        val theme = ClomniTheme.resolve(Fixture.aparConfig, systemIsDark = false, override)
        assertTrue(theme.isDark)
        assertEquals(RgbColor.parse("#0A66C2")!!.steps(1), theme.colors.primary)
        val panel = ClomniTheme.resolve(Fixture.aparConfig.let { it.copy(theme = it.theme.copy(mode = MessengerConfig.ThemeMode.DARK)) }, false)
        assertTrue("the panel's mode", panel.isDark)
        assertEquals("#27C87E", panel.colors.primary.hex)
    }

    @Test
    fun neutralTokens() {
        val light = ClomniTheme.make(null, dark = false)
        assertFalse(light.isDark)
        assertEquals(
            listOf("#FFFFFF", "#F5F6F8", "#F1F2F4", "#1B1D21", "#6A6E7A", "#E7E8EB", "#E5484D", "#FFF4CC", "#5C4400"),
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
            // #6A6E7A instead of the brief's #737780 (4.49:1 on white): secondary text reaches AA on every background.
            assertTrue(theme.colors.background.contrast(theme.colors.textSecondary) >= 4.5)
        }
        assertEquals(12f, ClomniTheme.Radius.card)
        assertEquals(40f, ClomniTheme.Size.cardOverlap)
        assertEquals(48f, ClomniTheme.Size.touchTarget)
        assertEquals(listOf(2.0, 10.0), ClomniTheme.Shadow.card.map { it.radius })
    }

    /** onPrimary without the server's colours: white or black by WCAG 4.5:1. */
    @Test
    fun textOnPrimary() {
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
        assertTrue(ClomniTheme.isDark(MessengerConfig.ThemeMode.DARK, systemIsDark = false))
        assertFalse(ClomniTheme.isDark(MessengerConfig.ThemeMode.LIGHT, systemIsDark = true))
        assertTrue(ClomniTheme.isDark(MessengerConfig.ThemeMode.SYSTEM, systemIsDark = true))
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
