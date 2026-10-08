package ai.clomni.messenger.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** GET /v1/mobile/config, version 2 (APPEARANCE-CONTRACT 1). */
class MessengerConfigTest {
    private val protocol = RecordingProtocol()

    private fun config(json: String): MessengerConfig = protocol.json.parseConfig(json)!!

    private val example = ProtocolFiles.read("fixtures/42-config-example.json")

    /** The server's config v2 for Example (protocol fixture 42), its colours taken as sent. */
    @Test
    fun theServersExampleConfig() {
        val config = config(example)
        assertEquals(12, config.version)
        assertEquals(
            MessengerConfig.Brand(
                name = "Example",
                logoUrl = "https://app.clomni.ai/v1/images/img_Lq3T8vXw2KpA9mZc4RbN",
                logoDarkUrl = null,
                primaryColor = "#1F9D63",
                headerStyle = MessengerConfig.HeaderStyle.GRADIENT,
                headerImageUrl = null,
                glow = false,
                colors = MessengerConfig.Colors(
                    light = MessengerConfig.Palette("#1F9D63", "#000000", "#E9F5EF", "#CEE9DD", "#1F9D63", "#177248", "#FFFFFF", "#0E482D"),
                    dark = MessengerConfig.Palette("#27C87E", "#000000", "#142520", "#173B2D", "#1F9D63", "#0E482D", "#FFFFFF", "#0E482D"),
                ),
            ),
            config.brand,
        )
        assertEquals(
            MessengerConfig.Team(
                show = true,
                avatars = listOf("leyla", "rauf", "nigar").map { "https://my.clomni.co/rails/active_storage/representations/redirect/$it.png" },
                replyTime = "Adətən bir neçə dəqiqəyə cavab veririk",
                replyTimeOffline = "Hazırda iş saatı deyil, sizə səhər cavab verəcəyik",
                officeHours = MessengerConfig.OfficeHours("Asia/Baku", openNow = true),
            ),
            config.team,
        )
        assertEquals("no bot picture: the SDK shows the logo", MessengerConfig.Bot("Clomni", null), config.bot)
        assertEquals(
            MessengerConfig.HomeCard.entries,
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
        assertEquals("Salam, {first_name}", config.strings["greeting_line1"])
        assertEquals("the panel's own", "Bizdən nəsə soruşun", config.strings["greeting_line2"])
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

    /** "messages" and "send" are always there; the panel's order otherwise; unknown cards and channels over five dropped. */
    @Test
    fun cardsAndChannels() {
        fun cards(json: String) = config("""{"home":{"cards":$json}}""").home.cards
        val messages = MessengerConfig.HomeCard.MESSAGES
        assertEquals(listOf(messages, MessengerConfig.HomeCard.CHANNELS, MessengerConfig.HomeCard.SEND), cards("""["channels","send"]"""))
        assertEquals(listOf(messages, MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.RECENT), cards("""["recent","articles"]"""))
        assertEquals(listOf(messages, MessengerConfig.HomeCard.SEND), cards("""["send","send"]"""))
        assertEquals(listOf(MessengerConfig.HomeCard.SEND, messages), cards("""["send","messages"]"""))
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
        val notHex = example.replace("\"#0E482D\"", "\"dark green\"")
        assertNull(config(notHex).brand.colors)
        assertNull(config("""{"brand":{}}""").brand.colors)
        // header_text came later: a server without it still sends usable colours, and the SDK works the text out.
        val withoutText = config(example.replace(Regex(""",\s*"header_text": "#FFFFFF""""), ""))
        assertEquals("#1F9D63", withoutText.brand.colors?.light?.headerFrom)
        assertNull(withoutText.brand.colors?.light?.headerText)
    }

    @Test
    fun languagesFromThePanel() {
        val minimal = config(ProtocolFiles.read("fixtures/43-config-minimal.json"))
        assertEquals(MessengerConfig.Languages(listOf("az"), "az"), minimal.languages)
        assertEquals("one language on: always it", "az", minimal.languages.pick("en", "ru"))
        val example = config(ProtocolFiles.read("fixtures/42-config-example.json")).languages
        assertEquals("the host's first", "ru", example.pick("ru", "en"))
        assertEquals("then the phone's", "en", example.pick("de", "en-GB"))
        assertEquals("then the default", "az", example.pick(null, "tr_TR"))
        val two = config("""{"languages":{"enabled":["en","ru"],"default":"ru"}}""").languages
        assertEquals("a language that is off is not spoken", "ru", two.pick("az", "az"))
        assertEquals("no config yet: the phone", "ru", (null as MessengerConfig?).speaks(null, "ru-RU"))
        // The earlier array, a default that is off, nothing usable.
        assertEquals(MessengerConfig.Languages(listOf("en", "az"), "en"), config("""{"languages":["en","az","xx"]}""").languages)
        assertEquals("en", config("""{"languages":{"enabled":["en"],"default":"az"}}""").languages.default)
        assertEquals(MessengerConfig.Languages(), config("""{"languages":{"enabled":[],"default":"az"}}""").languages)
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
        assertEquals("all three, az the default", MessengerConfig.Languages(), config.languages)
        assertTrue(config.poweredBy)
        assertFalse(config.startsWithFlow)
        assertTrue(config.sounds)
    }

    @Test
    fun aNewConversationThatStartsWithItsFlowAndTheSounds() {
        assertTrue(config(example).startsWithFlow)
        assertFalse(config(ProtocolFiles.read("fixtures/59-config-wordmark.json")).startsWithFlow)
        assertTrue(config(example).sounds)
        assertFalse(config("""{"sounds":false}""").sounds)
    }

    /** brand.logo_style "wordmark" with its picture; the mark otherwise, also for a style without a picture. */
    @Test
    fun theWrittenLogo() {
        val wordmark = config(ProtocolFiles.read("fixtures/59-config-wordmark.json")).brand
        assertEquals("https://app.clomni.ai/v1/images/img_Wm7Qk2Lx9PzR4sTv8NcY", wordmark.wordmarkUrl)
        assertNull(wordmark.wordmarkDarkUrl)
        assertNull(config(example).brand.wordmarkUrl)
        val mark = config("""{"brand":{"logo_style":"mark","wordmark_url":"https://x/w.png"}}""").brand
        assertNull("the panel chose the mark", mark.wordmarkUrl)
        assertNull(config("""{"brand":{"logo_style":"wordmark"}}""").brand.wordmarkUrl)
        val dark = config("""{"brand":{"logo_style":"wordmark","wordmark_url":"https://x/w.png","wordmark_dark_url":"https://x/d.png"}}""")
        assertEquals("https://x/d.png", dark.brand.wordmarkDarkUrl)
        assertEquals("1200 wide at most", "https://x/w.png?w=600&format=webp", ai.clomni.messenger.presentation.ImageSizing.url("https://x/w.png", ai.clomni.messenger.presentation.ImageSizing.Kind.WORDMARK, 216f, 2.75f))
    }

    /** home.title_scale and brand.logo_scale, % (70–140 and 60–200); title_size from an older draft maps to 85/100/120. */
    @Test
    fun theGreetingsAndTheLogosSize() {
        fun title(json: String) = config("""{"home":$json}""").home.titleScale
        assertEquals(115, title("""{"title_scale":115}"""))
        assertEquals("clamped", 140, title("""{"title_scale":300}"""))
        assertEquals(85, title("""{"title_size":"s"}"""))
        assertEquals(120, title("""{"title_size":"l"}"""))
        assertEquals(100, title("{}"))
        fun logo(json: String) = config("""{"brand":$json}""").brand.logoScale
        assertEquals(150, logo("""{"logo_scale":150}"""))
        assertEquals("clamped", 60, logo("""{"logo_scale":10}"""))
        assertEquals(100, logo("{}"))
        assertEquals(MessengerConfig.HomeCard.entries, config("{}").home.cards)
        assertEquals("the list and send always there", listOf(MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.NEWS), config("""{"home":{"cards":["news"]}}""").home.cards)
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
