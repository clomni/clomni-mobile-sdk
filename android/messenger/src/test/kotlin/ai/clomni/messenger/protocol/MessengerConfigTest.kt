package ai.clomni.messenger.protocol

import ai.clomni.messenger.presentation.APAR_CONFIG_V2
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** GET /v1/mobile/config, version 2 (APPEARANCE-CONTRACT 1). */
class MessengerConfigTest {
    private val protocol = RecordingProtocol()

    private fun config(json: String): MessengerConfig = protocol.json.parseConfig(json)!!

    @Test
    fun theContractsExample() {
        val config = config(APAR_CONFIG_V2)
        assertEquals(12, config.version)
        assertEquals(
            MessengerConfig.Brand(
                name = "Apar",
                logoUrl = "https://app.clomni.ai/a/apar.png",
                logoDarkUrl = null,
                primaryColor = "#1F9D63",
                headerStyle = MessengerConfig.HeaderStyle.GRADIENT,
                headerImageUrl = null,
                glow = false,
                colors = MessengerConfig.Colors(
                    light = MessengerConfig.Palette("#1F9D63", "#FFFFFF", "#E9F5EF", "#C6E6D5", "#3FB37C", "#13734A", "#FFFFFF"),
                    dark = MessengerConfig.Palette("#34B57A", "#0B0C0E", "#16241D", "#24503A", "#1F9D63", "#0E4F33", "#FFFFFF"),
                ),
            ),
            config.brand,
        )
        assertEquals(
            MessengerConfig.Team(
                show = true,
                avatars = listOf("https://app.clomni.ai/a/leyla.png", "https://app.clomni.ai/a/rauf.png", "https://app.clomni.ai/a/nigar.png"),
                replyTime = "Adətən bir neçə dəqiqəyə cavab veririk",
                replyTimeOffline = "Hazırda iş saatı deyil, sizə səhər cavab verəcəyik",
                officeHours = MessengerConfig.OfficeHours("Asia/Baku", openNow = true),
            ),
            config.team,
        )
        assertEquals(MessengerConfig.Bot("Clomni", "https://app.clomni.ai/a/bot.png"), config.bot)
        assertEquals(
            listOf(MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.RECENT, MessengerConfig.HomeCard.CHANNELS),
            config.home.cards,
        )
        assertEquals(listOf("instagram", "whatsapp", "linkedin", "email"), config.home.channels.map { it.type })
        assertEquals(
            MessengerConfig.ThemeSettings(
                MessengerConfig.ThemeMode.SYSTEM,
                MessengerConfig.Launcher(enabled = false, position = MessengerConfig.LauncherPosition.RIGHT, bottomPadding = 20),
            ),
            config.theme,
        )
        assertEquals(MessengerConfig.Composer(attachments = true, emoji = true), config.composer)
        assertEquals("Salam, {first_name} 👋", config.strings["greeting_line1"])
        assertEquals(MessengerConfig.Limits(10, 25, 4000), config.limits)
        assertTrue(config.poweredBy)
        assertTrue(protocol.warnings.isEmpty())
    }

    @Test
    fun headerStylesThemeAndLauncher() {
        val image = config(
            """{"brand":{"header_style":"image","header_image_url":"https://app.clomni.ai/v1/images/h","glow":true,
                 "logo_dark_url":"https://app.clomni.ai/v1/images/d"},
               "theme":{"mode":"dark","launcher":{"enabled":true,"position":"left","bottom_padding":64}},
               "powered_by":false,"team":{"show":false}}""",
        )
        assertEquals(MessengerConfig.HeaderStyle.IMAGE, image.brand.headerStyle)
        assertEquals("https://app.clomni.ai/v1/images/h", image.brand.headerImageUrl)
        assertTrue(image.brand.glow)
        assertEquals("https://app.clomni.ai/v1/images/d", image.brand.logoDarkUrl)
        assertEquals(MessengerConfig.ThemeMode.DARK, image.theme.mode)
        assertEquals(MessengerConfig.Launcher(true, MessengerConfig.LauncherPosition.LEFT, 64), image.theme.launcher)
        assertFalse(image.poweredBy)
        assertFalse(image.team.show)
        assertEquals(MessengerConfig.HeaderStyle.SOLID, config("""{"brand":{"header_style":"solid"}}""").brand.headerStyle)
        assertEquals(MessengerConfig.ThemeMode.LIGHT, config("""{"theme":{"mode":"light"}}""").theme.mode)
        assertEquals("0–200", 200, config("""{"theme":{"launcher":{"bottom_padding":900}}}""").theme.launcher.bottomPadding)
    }

    /** "send" is always there; the panel's order otherwise; unknown cards and channels over five are dropped. */
    @Test
    fun cardsAndChannels() {
        fun cards(json: String) = config("""{"home":{"cards":$json}}""").home.cards
        assertEquals(listOf(MessengerConfig.HomeCard.CHANNELS, MessengerConfig.HomeCard.SEND), cards("""["channels","send"]"""))
        assertEquals(listOf(MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.RECENT), cards("""["recent","articles"]"""))
        assertEquals(listOf(MessengerConfig.HomeCard.SEND), cards("""["send","send"]"""))
        assertEquals(MessengerConfig.HomeCard.entries, config("{}").home.cards)
        val seven = (1..7).joinToString(",") { """{"type":"link","url":"https://x/$it"}""" }
        assertEquals(5, config("""{"home":{"channels":[$seven]}}""").home.channels.size)
    }

    /** The server's colours are taken whole or not at all: the SDK then derives them. */
    @Test
    fun brokenColoursAreDerivedInstead() {
        val missing = config("""{"brand":{"colors":{"light":{"primary":"#1F9D63"}}}}""")
        assertNull(missing.brand.colors)
        assertEquals("brand.colors incomplete; the SDK derives the colours", protocol.warnings.last())
        val notHex = APAR_CONFIG_V2.replace("\"#0E4F33\"", "\"dark green\"")
        assertNull(config(notHex).brand.colors)
        assertNull(config("""{"brand":{}}""").brand.colors)
        // header_text came later: a server without it still sends usable colours, and the SDK works the text out.
        val withoutText = config(APAR_CONFIG_V2.replace(", \"header_text\": \"#FFFFFF\"", ""))
        assertEquals("#3FB37C", withoutText.brand.colors?.light?.headerFrom)
        assertNull(withoutText.brand.colors?.light?.headerText)
    }

    @Test
    fun anEmptyObjectIsAConfigOfDefaults() {
        val config = config("{}")
        assertEquals(0, config.version)
        assertEquals("", config.brand.name)
        assertEquals(MessengerConfig.Brand.DEFAULT_PRIMARY_COLOR, config.brand.primaryColor)
        assertEquals(MessengerConfig.HeaderStyle.GRADIENT, config.brand.headerStyle)
        assertFalse(config.brand.glow)
        assertTrue(config.team.show)
        assertNull(config.team.replyTimeOffline)
        assertEquals(MessengerConfig.ThemeMode.SYSTEM, config.theme.mode)
        assertFalse(config.theme.launcher.enabled)
        assertEquals(listOf("az"), config.languages)
        assertTrue(config.poweredBy)
    }

    /** The v1 fixtures (until the server's v2 ones arrive) still read: their old fields are ignored. */
    @Test
    fun aVersionOneConfigReadsWithDefaults() {
        val old = protocol.json.parseConfig(ProtocolFiles.read("fixtures/42-config-apar.json"))!!
        assertEquals("Apar", old.brand.name)
        assertNull(old.brand.colors)
        assertFalse("v1's launcher.visible is not v2's theme.launcher.enabled", old.theme.launcher.enabled)
        assertEquals("unknown v1 card names: send only", listOf(MessengerConfig.HomeCard.SEND), old.home.cards)
    }

    @Test
    fun invalidColourFallsBackToTheDefault() {
        assertEquals(MessengerConfig.Brand.DEFAULT_PRIMARY_COLOR, config("""{"brand":{"primary_color":"green"}}""").brand.primaryColor)
        assertEquals("brand.primary_color \"green\" is not #RRGGBB; default colour used", protocol.warnings.single())
    }

    @Test
    fun nextOpeningTime() {
        val closed = config("""{"team":{"office_hours":{"open_now":false,"next_open_at":"2026-10-02T05:00:00Z"}}}""")
        assertEquals(MessengerConfig.OfficeHours(null, openNow = false, nextOpenAt = 1_790_917_200_000L), closed.team.officeHours)
        val broken = config("""{"team":{"office_hours":{"open_now":false,"next_open_at":"sabah"}}}""")
        assertNull(broken.team.officeHours?.nextOpenAt)
    }

    @Test
    fun notAConfig() {
        assertNull(protocol.json.parseConfig("[]"))
        assertNull(protocol.json.parseConfig("<html>"))
        assertEquals(2, protocol.warnings.size)
    }
}
