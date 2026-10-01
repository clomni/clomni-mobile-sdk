package ai.clomni.messenger.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessengerConfigTest {

    private val protocol = RecordingProtocol()

    private fun fixture(name: String): MessengerConfig = protocol.json.parseConfig(ProtocolFiles.read("fixtures/$name"))!!

    private fun config(json: String): MessengerConfig = protocol.json.parseConfig(json)!!

    @Test
    fun fullConfig() {
        assertEquals(
            MessengerConfig(
                brand = MessengerConfig.Brand(
                    name = "Apar",
                    logoUrl = "https://app.clomni.ai/a/apar.png",
                    primaryColor = "#1F9D63",
                    onPrimaryColor = "#FFFFFF",
                    theme = MessengerConfig.Theme.SYSTEM,
                ),
                launcher = MessengerConfig.Launcher(false, MessengerConfig.LauncherPosition.RIGHT, 20, "default"),
                home = MessengerConfig.Home(
                    greetingTitle = "Necə kömək edə bilərik?",
                    greetingSubtitle = "Bizdən nəsə soruşun və ya fikrinizi bildirin",
                    showTeamAvatars = true,
                    channels = listOf(
                        MessengerConfig.HomeChannel("instagram", "https://instagram.com/apar.az"),
                        MessengerConfig.HomeChannel("whatsapp", "https://wa.me/994501234567"),
                        MessengerConfig.HomeChannel("linkedin", "https://linkedin.com/company/apar"),
                        MessengerConfig.HomeChannel("email", "mailto:support@apar.az"),
                    ),
                    cards = listOf(MessengerConfig.HomeCard.RECENT_CONVERSATION, MessengerConfig.HomeCard.NEW_CONVERSATION),
                ),
                team = MessengerConfig.Team(
                    avatars = listOf(
                        "https://app.clomni.ai/a/leyla.png",
                        "https://app.clomni.ai/a/rauf.png",
                        "https://app.clomni.ai/a/nigar.png",
                    ),
                    replyTime = "Adətən bir neçə dəqiqəyə cavab veririk",
                    officeHours = MessengerConfig.OfficeHours("Asia/Baku", true),
                ),
                bot = MessengerConfig.Bot("Clomni", "https://app.clomni.ai/a/bot.png"),
                composer = MessengerConfig.Composer("Mesaj yazın…", attachments = true, emoji = true),
                languages = listOf("az", "en", "ru"),
                strings = mapOf(
                    "today" to "Bu gün",
                    "yesterday" to "Dünən",
                    "send" to "Göndər",
                    "new_conversation" to "Bizə mesaj göndərin",
                    "sent" to "Göndərildi",
                    "read" to "Oxundu",
                    "choose_above" to "Yuxarıdakı variantlardan birini seçin",
                ),
                limits = MessengerConfig.Limits(10, 25, 4000),
            ),
            fixture("42-config-apar.json"),
        )
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun minimalConfigGetsDefaults() {
        val config = fixture("43-config-minimal.json")
        assertEquals(
            MessengerConfig.Brand("Clomni, Inc.", null, "#10A670", null, MessengerConfig.Theme.SYSTEM),
            config.brand,
        )
        assertEquals(MessengerConfig.Launcher(false, MessengerConfig.LauncherPosition.RIGHT, 0, "default"), config.launcher)
        assertEquals(
            MessengerConfig.Home(null, null, false, emptyList(), listOf(MessengerConfig.HomeCard.NEW_CONVERSATION)),
            config.home,
        )
        assertEquals(MessengerConfig.Team(emptyList(), null, null), config.team)
        assertEquals(MessengerConfig.Bot("Clomni", null), config.bot)
        assertEquals(MessengerConfig.Composer(null, attachments = true, emoji = true), config.composer)
        assertEquals(listOf("az"), config.languages)
        assertEquals(emptyMap<String, String>(), config.strings)
        assertEquals(MessengerConfig.Limits(10, 25, 4000), config.limits)
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun invalidColourFallsBackToTheDefault() {
        assertEquals(MessengerConfig.DEFAULT_PRIMARY_COLOR, fixture("96-invalid-config-color.json").brand.primaryColor)
        assertTrue(protocol.warnings.toString(), protocol.warnings.single().contains("'green'"))
    }

    @Test
    fun emptyObjectIsAConfigOfDefaults() {
        val config = config("{}")
        assertEquals(MessengerConfig.DEFAULT_PRIMARY_COLOR, config.brand.primaryColor)
        assertEquals("", config.brand.name)
        assertEquals(MessengerConfig.HomeCard.entries, config.home.cards)
        assertEquals("", config.bot.name)
        assertEquals(1, protocol.warnings.size)
    }

    @Test
    fun brokenValuesAreSkipped() {
        val config = config(
            """{
              "brand": {"name": "X", "primary_color": "#abcdef", "on_primary_color": "white", "theme": "dark"},
              "launcher": {"visible": true, "position": "left", "bottom_padding": -4},
              "home": {
                "channels": [{"type": "telegram", "url": "https://t.me/x"}, {"type": "x"}, {"url": "https://y"}, "z"],
                "cards": ["new_conversation", "articles", 3]
              },
              "team": {"avatars": ["https://a", 1, null]},
              "languages": ["de", "en", "en"],
              "strings": {"send": "Send", "count": 3},
              "limits": {"image_mb": 0, "file_mb": 50, "text_chars": "many"}
            }""",
        )
        assertEquals("#abcdef", config.brand.primaryColor)
        assertNull(config.brand.onPrimaryColor)
        assertEquals(MessengerConfig.Theme.DARK, config.brand.theme)
        assertEquals(MessengerConfig.Launcher(true, MessengerConfig.LauncherPosition.LEFT, 0, "default"), config.launcher)
        assertEquals(listOf(MessengerConfig.HomeChannel("telegram", "https://t.me/x")), config.home.channels)
        assertEquals(listOf(MessengerConfig.HomeCard.NEW_CONVERSATION), config.home.cards)
        assertEquals(listOf("https://a"), config.team.avatars)
        assertEquals(listOf("en"), config.languages)
        assertEquals(mapOf("send" to "Send"), config.strings)
        assertEquals(MessengerConfig.Limits(10, 50, 4000), config.limits)
        assertEquals(MessengerConfig.Theme.LIGHT, config("""{"brand":{"theme":"light"}}""").brand.theme)
        assertEquals(listOf("az"), config("""{"languages":["de"]}""").languages)
    }

    @Test
    fun briefExample() {
        val config = protocol.json.parseConfig(ProtocolFiles.read("examples/brief/s6.3-config.json"))!!
        assertEquals("Apar", config.brand.name)
        assertEquals("Dün", config.strings["yesterday"])
    }

    @Test
    fun notAConfig() {
        assertNull(protocol.json.parseConfig("[]"))
        assertNull(protocol.json.parseConfig("<html>"))
        assertEquals(2, protocol.warnings.size)
    }
}
