package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

/** protocol/fixtures as the presentation tests use them. */
internal object Fixture {
    private val protocol = ProtocolJson()

    val aparConfig: MessengerConfig get() = protocol.parseConfig(APAR_CONFIG_V2)!!
    val minimalConfig: MessengerConfig get() = protocol.parseConfig(ProtocolFiles.read("fixtures/43-config-minimal.json"))!!

    /** A conversation whose last message is the fixture [message] (created at 2026-10-01T10:30Z, or [at]). */
    fun conversation(
        id: String,
        message: String?,
        unread: Int = 0,
        assignee: String? = null,
        at: String = "2026-10-01T10:30:00Z",
    ): Conversation {
        val last = message?.let {
            ProtocolFiles.read("fixtures/$it").replace(Regex("\"created_at\": \"[^\"]*\""), "\"created_at\": \"$at\"")
        } ?: "null"
        val person = assignee?.let { """{"name":"$it","avatar_url":"https://app.clomni.ai/a/${it.lowercase()}.png"}""" } ?: "null"
        return protocol.parseConversation(
            """{"id":"$id","status":"open","assignee":$person,"unread_count":$unread,"last_message":$last,
               "created_at":"2026-09-30T08:00:00Z"}""",
        )!!
    }
}

class PresenterTest {
    /** 2026-10-01T10:32Z: two minutes after the fixtures' messages. */
    private val now = 1_790_850_720_000L
    private val utc = TimeZone.getTimeZone("UTC")

    private fun presenter(language: String = "az", config: MessengerConfig? = Fixture.aparConfig) =
        HomePresenter(ClomniStrings(language, config?.strings.orEmpty()), utc, now)

    private fun snapshot(
        config: MessengerConfig? = Fixture.aparConfig,
        conversations: List<Conversation> = emptyList(),
        user: String? = "Aysel Məmmədova",
    ) = MessengerSnapshot(
        config = config,
        conversations = conversations,
        userName = user,
        configLoad = MessengerSnapshot.Load.LOADED,
        conversationsLoad = MessengerSnapshot.Load.LOADED,
    )

    @Test
    fun header() {
        val header = presenter().home(snapshot()).header
        assertEquals("Apar", header.brandName)
        assertEquals("A", header.brandInitial)
        assertEquals("https://app.clomni.ai/a/apar.png", header.logoUrl)
        assertEquals(3, header.teamAvatars.size)
        assertEquals("Salam, Aysel 👋", header.greeting)
        assertEquals("Necə kömək edə bilərik?", header.title)
        assertEquals("Bağla", header.closeLabel)

        assertEquals("Salam 👋", presenter().home(snapshot(user = null)).header.greeting)
        assertEquals("Salam 👋", presenter().home(snapshot(user = "   ")).header.greeting)
        // The SDK's own texts ({first_name}); the panel's come with the config in its language.
        val english = HomePresenter(ClomniStrings("en"), utc, now)
        assertEquals("Hi, Aysel 👋", english.home(snapshot(user = "Aysel Məmmədova")).header.greeting)
        assertEquals("Hi 👋", english.home(snapshot(user = null)).header.greeting)
        val fullName = ClomniStrings("az", mapOf("greeting_line1" to "Xoş gəldiniz, {name}!"))
        assertEquals("Xoş gəldiniz, Aysel Məmmədova!", fullName.greeting("Aysel Məmmədova"))

        val minimal = presenter(config = Fixture.minimalConfig).home(snapshot(Fixture.minimalConfig)).header
        assertEquals("the SDK's text when the config has none", "Necə kömək edə bilərik?", minimal.title)
        assertNull(minimal.logoUrl)
        assertEquals("C", minimal.brandInitial)
    }

    @Test
    fun cardsFollowTheConfig() {
        val operatorReply = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)
        val apar = presenter().home(snapshot(Fixture.aparConfig, listOf(operatorReply)))
        assertEquals(HomeScreen.Phase.READY, apar.phase)
        assertEquals("Bizə mesaj göndərin", apar.newConversation?.title)
        assertEquals("Adətən bir neçə dəqiqəyə cavab veririk", apar.newConversation?.subtitle)
        assertEquals("Bizə mesaj göndərin. Adətən bir neçə dəqiqəyə cavab veririk", apar.newConversation?.accessibilityLabel)
        assertEquals("Son mesaj", apar.recent?.label)
        assertEquals("Bizi izləyin", apar.channels?.label)
        assertEquals(listOf("Instagram", "WhatsApp", "LinkedIn", "E-poçt"), apar.channels?.items?.map { it.accessibilityLabel })
        assertNull(apar.offline)
        assertNull(apar.failure)

        // Minimal config: only "new conversation"; no channels, so no "Bizi izləyin"; no reply time.
        val minimal = presenter(config = Fixture.minimalConfig).home(snapshot(Fixture.minimalConfig, listOf(operatorReply)))
        assertNotNull(minimal.newConversation)
        assertNull(minimal.newConversation?.subtitle)
        assertNull("the config does not list recent_conversation", minimal.recent)
        assertNull(minimal.channels)
        assertTrue(minimal.header.teamAvatars.isEmpty())
        // Without a config the cards are both on (the default), and the team is not shown.
        val noCards = presenter(config = null).home(snapshot(null, listOf(operatorReply)))
        assertNotNull(noCards.newConversation)
        assertNotNull(noCards.recent)
    }

    @Test
    fun recentMessageIsHiddenWithoutAConversation() {
        assertNull(presenter().home(snapshot(Fixture.aparConfig, emptyList())).recent)
        val empty = Fixture.conversation("conv_new", null)
        assertNull("nothing written in it yet", presenter().home(snapshot(Fixture.aparConfig, listOf(empty))).recent)
    }

    @Test
    fun recentMessageRow() {
        val fromOperator = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 2)
        val row = presenter().home(snapshot(Fixture.aparConfig, listOf(fromOperator))).recent!!.row
        assertEquals("conv_1", row.id)
        assertEquals("Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər", row.preview)
        assertEquals("Leyla · 2 dəq", row.detail)
        assertEquals("L", row.initial)
        assertEquals("https://app.clomni.ai/a/leyla.png", row.avatarUrl)
        assertTrue(row.unread)
        assertEquals(
            "Leyla, 2 dəq: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər. Oxunmamış",
            row.accessibilityLabel,
        )

        // The user wrote last: "Siz", and the other side's face.
        val fromUser = Fixture.conversation("conv_2", "03-text-user.json", assignee = "Rauf", at = "2026-10-01T10:31:50Z")
        val mine = presenter().row(fromUser, Fixture.aparConfig)!!
        assertEquals("Siz · indi", mine.detail)
        assertEquals("R", mine.initial)
        assertEquals("https://app.clomni.ai/a/rauf.png", mine.avatarUrl)
        assertFalse(mine.unread)
        assertFalse(mine.accessibilityLabel.contains("Oxunmamış"))

        // A bot's quick replies: its fallback text on one line, the bot's name and avatar.
        val fromBot = Fixture.conversation("conv_3", "10-apar-level2-S-chips.json")
        val bot = presenter().row(fromBot, Fixture.aparConfig)!!
        assertEquals(
            "Probleminiz nə ilə bağlıdır? Parking zona / Velosiped dayandı / Texniki nasazlıq / Kilidləmə / Əşyamı itirdim",
            bot.preview,
        )
        assertEquals("Clomni · 2 dəq", bot.detail)
        assertEquals("https://app.clomni.ai/a/bot.png", bot.avatarUrl)

        // A system message: the brand speaks.
        val system = presenter(config = Fixture.minimalConfig)
            .row(Fixture.conversation("conv_4", "23-system-operator-joined.json"), Fixture.minimalConfig)!!
        assertEquals("Clomni, Inc. · 2 dəq", system.detail)
        assertEquals("Leyla söhbətə qoşuldu", system.preview)

        // An operator without a name: the assignee's, then the brand's.
        val nameless = Fixture.conversation("conv_5", "31-operator-no-avatar.json", assignee = "Nigar")
        assertEquals("Leyla · 2 dəq", presenter().row(nameless, Fixture.aparConfig)!!.detail)
        assertEquals("C", presenter(config = null).row(Fixture.conversation("conv_6", "01-text-bot.json"), null)!!.initial)
    }

    @Test
    fun markdownIsRemovedFromPreviews() {
        fun preview(text: String) = HomePresenter.plainText(
            Message("msg_1", null, "conv_1", "text", Sender(SenderType.BOT), now, 1, "az", null, MessageContent.Text(text), text),
        )
        assertEquals("Salam! Xoş gəldiniz şərtlər 2*3", preview("**Salam!** *Xoş* gəldiniz\n\n[şərtlər](https://apar.az) 2*3"))
        assertEquals("👍🙏", preview("👍🙏"))
        // A letter of the alphabet before "*" is a word character on every platform.
        assertEquals("ə*x*", preview("ə*x*"))
    }

    @Test
    fun tabDot() {
        val list = listOf(Fixture.conversation("conv_1", "02-text-operator-markdown.json"))
        val quiet = snapshot(Fixture.aparConfig, list)
        assertFalse(presenter().home(quiet).tabs.messagesUnread)
        assertEquals("Mesajlar", presenter().home(quiet).tabs.messagesAccessibilityLabel)
        val tabs = presenter().home(quiet.copy(unreadTotal = 1)).tabs
        assertTrue(tabs.messagesUnread)
        assertEquals("Ana səhifə", tabs.home)
        assertEquals("Mesajlar, Oxunmamış mesaj var", tabs.messagesAccessibilityLabel)
        val unreadInList = snapshot(Fixture.aparConfig, listOf(Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)))
        assertTrue("before the first unread.changed", presenter().home(unreadInList).tabs.messagesUnread)
    }

    @Test
    fun loadingFailureAndOffline() {
        val nothing = MessengerSnapshot()
        assertEquals(HomeScreen.Phase.LOADING, presenter(config = null).home(nothing).phase)
        assertEquals(HomeScreen.Phase.LOADING, presenter(config = null).messages(nothing).phase)
        val down = nothing.copy(configLoad = MessengerSnapshot.Load.FAILED, conversationsLoad = MessengerSnapshot.Load.FAILED)
        val failed = presenter(config = null).home(down)
        assertEquals(HomeScreen.Phase.FAILED, failed.phase)
        assertEquals(HomeScreen.Failure("Nəsə səhv getdi", "Yenidən cəhd et"), failed.failure)
        assertEquals(HomeScreen.Phase.FAILED, presenter(config = null).messages(down).phase)

        // A cached config is shown even when the refresh failed.
        val cached = snapshot().copy(configLoad = MessengerSnapshot.Load.FAILED, isOffline = true)
        val home = presenter().home(cached)
        assertEquals(HomeScreen.Phase.READY, home.phase)
        assertNull(home.failure)
        assertEquals("İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq", home.offline)
        assertEquals(home.offline, presenter().messages(cached).offline)
    }

    @Test
    fun messagesTab() {
        val list = listOf(
            Fixture.conversation("conv_2", "03-text-user.json"),
            Fixture.conversation("conv_new", null),
            Fixture.conversation("conv_1", "02-text-operator-markdown.json"),
        )
        val messages = presenter().messages(snapshot(Fixture.aparConfig, list))
        assertEquals("Mesajlar", messages.title)
        assertEquals(HomeScreen.Phase.READY, messages.phase)
        assertEquals(listOf("conv_2", "conv_1"), messages.rows.map { it.id })
        assertNull(messages.empty)
        assertEquals("Bizə mesaj göndərin", messages.newConversation.title)

        val empty = presenter().messages(snapshot(Fixture.aparConfig, emptyList()))
        assertEquals("Hələ söhbət yoxdur", empty.empty)
        assertEquals(HomeScreen.Phase.READY, empty.phase)
        assertNull(empty.failure)

        val stale = snapshot(Fixture.aparConfig, list).copy(conversationsLoad = MessengerSnapshot.Load.FAILED)
        assertEquals("the cached list stays", HomeScreen.Phase.READY, presenter().messages(stale).phase)
        assertEquals("Пока нет переписки", presenter("ru").messages(snapshot(Fixture.aparConfig, emptyList())).empty)
    }

    @Test
    fun channelStyles() {
        val strings = ClomniStrings("az")
        fun item(type: String, url: String) = ChannelItem.of(type, url, strings)
        assertEquals(ChannelItem.Tint.Brand(RgbColor.parse("#E4405F")!!), item("instagram", "https://instagram.com/apar").tint)
        assertEquals(ChannelItem.Icon.WHATSAPP, item("WhatsApp", "https://wa.me/1").icon)
        assertEquals(ChannelItem.Tint.Brand(RgbColor.parse("#0A66C2")!!), item("linkedin", "https://linkedin.com/x").tint)
        assertEquals(ChannelItem.Tint.Neutral, item("email", "mailto:a@b.az").tint)
        assertEquals(ChannelItem.Icon.EMAIL, item("email", "mailto:a@b.az").icon)
        assertEquals("a mailto: link is email", "E-poçt", item("support", "mailto:a@b.az").accessibilityLabel)
        assertEquals("Telefon", item("call", "tel:+994501234567").accessibilityLabel)
        assertEquals(ChannelItem.Icon.PHONE, item("call", "tel:+994501234567").icon)
        assertEquals("black would vanish in dark mode", ChannelItem.Tint.Neutral, item("x", "https://x.com/apar").tint)
        assertEquals(ChannelItem.Icon.X, item("twitter", "https://twitter.com/apar").icon)
        val unknown = item("mastodon", "https://social.az/@apar")
        assertEquals(ChannelItem.Icon.LINK, unknown.icon)
        assertEquals(ChannelItem.Tint.Neutral, unknown.tint)
        assertEquals("social.az", unknown.accessibilityLabel)
        assertEquals("not a URL: the text itself", "nə isə", item("site", "nə isə").accessibilityLabel)
        assertNotEquals(item("instagram", "https://a").id, item("instagram", "https://b").id)
        val all = listOf("telegram", "facebook", "messenger", "youtube", "tiktok").map { item(it, "https://$it.com").icon }
        assertEquals(
            listOf(ChannelItem.Icon.TELEGRAM, ChannelItem.Icon.FACEBOOK, ChannelItem.Icon.MESSENGER, ChannelItem.Icon.YOUTUBE, ChannelItem.Icon.TIKTOK),
            all,
        )
    }
}
