package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.NewsItem
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

    val exampleConfig: MessengerConfig get() = protocol.parseConfig(ProtocolFiles.read("fixtures/42-config-example.json"))!!
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

    private fun presenter(language: String = "az", config: MessengerConfig? = Fixture.exampleConfig) =
        HomePresenter(ClomniStrings(language, config?.strings.orEmpty()), utc, now)

    private fun snapshot(
        config: MessengerConfig? = Fixture.exampleConfig,
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
        assertEquals("Example", header.brandName)
        assertEquals("E", header.brandInitial)
        assertEquals("https://app.clomni.ai/v1/images/img_Lq3T8vXw2KpA9mZc4RbN", header.logoUrl)
        assertEquals(3, header.teamAvatars.size)
        assertEquals("Salam, Aysel", header.greeting)
        assertEquals("the panel's line", "Bizdən nəsə soruşun", header.title)
        assertEquals("Bağla", header.closeLabel)

        assertEquals("Salam", presenter().home(snapshot(user = null)).header.greeting)
        assertEquals("Salam", presenter().home(snapshot(user = "   ")).header.greeting)
        // The SDK's own texts ({first_name}); the panel's come with the config in its language.
        val english = HomePresenter(ClomniStrings("en"), utc, now)
        assertEquals("Hi, Aysel", english.home(snapshot(user = "Aysel Məmmədova")).header.greeting)
        assertEquals("Hi", english.home(snapshot(user = null)).header.greeting)
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
        val example = presenter().home(snapshot(Fixture.exampleConfig, listOf(operatorReply)))
        assertEquals(HomeScreen.Phase.READY, example.phase)
        assertEquals("Bizə mesaj göndərin", example.newConversation?.title)
        assertEquals("Adətən bir neçə dəqiqəyə cavab veririk", example.newConversation?.subtitle)
        assertEquals("Bizə mesaj göndərin. Adətən bir neçə dəqiqəyə cavab veririk", example.newConversation?.accessibilityLabel)
        assertEquals("Ən son mesaj", example.recent?.label)
        assertEquals("Bizi izləyin", example.channels?.label)
        assertEquals(listOf("Instagram", "WhatsApp", "LinkedIn", "E-poçt"), example.channels?.items?.map { it.accessibilityLabel })
        assertNull(example.offline)
        assertNull(example.failure)

        // Minimal config (fixture 43): only "new conversation"; no channels, so no "Bizi izləyin"; the team hidden.
        val minimal = presenter(config = Fixture.minimalConfig).home(snapshot(Fixture.minimalConfig, listOf(operatorReply)))
        assertNotNull(minimal.newConversation)
        assertEquals("Adətən bir neçə dəqiqəyə cavab veririk", minimal.newConversation?.subtitle)
        assertNull("the config does not list recent_conversation", minimal.recent)
        assertNull(minimal.channels)
        assertTrue(minimal.header.teamAvatars.isEmpty())
        // Without a config the cards are both on (the default), and the team is not shown.
        val noCards = presenter(config = null).home(snapshot(null, listOf(operatorReply)))
        assertNotNull(noCards.newConversation)
        assertNotNull(noCards.recent)
    }

    /** APPEARANCE-CONTRACT 1 and 4: what the panel publishes reaches Home. */
    @Test
    fun appearanceFromThePanel() {
        val withMessage = listOf(Fixture.conversation("conv_1", "02-text-operator-markdown.json"))
        val example = presenter().home(snapshot(Fixture.exampleConfig, withMessage))
        assertEquals(listOf(MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.RECENT, MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.CHANNELS), example.order)
        assertEquals("Powered by", example.poweredBy)
        assertEquals(MessengerConfig.HeaderStyle.GRADIENT, example.header.style)

        val config = ProtocolJson().parseConfig(
            """{"brand":{"name":"Example","primary_color":"#1F9D63","logo_url":"https://app.clomni.ai/v1/images/logo",
                        "logo_dark_url":"https://app.clomni.ai/v1/images/logo-dark",
                        "header_style":"image","header_image_url":"https://app.clomni.ai/v1/images/head","glow":true},
               "team":{"show":false,"avatars":["https://app.clomni.ai/a/leyla.png"],"reply_time":"Tez",
                       "reply_time_offline":"Səhər cavab veririk","office_hours":{"open_now":false}},
               "bot":{"name":"Clomni","avatar_url":null},
               "home":{"cards":["channels","recent","send"],"channels":[{"type":"instagram","url":"https://instagram.com/example"}]},
               "strings":{"greeting_line1":"Xoş gəldin, {first_name}!","greeting_line2":"Sualınız var?","send_card_title":"Yazın"},
               "powered_by":false}""",
        )!!
        val home = presenter(config = config).home(snapshot(config, withMessage))
        assertEquals(
            "the panel's order, the list's card always there",
            listOf(MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.CHANNELS, MessengerConfig.HomeCard.RECENT, MessengerConfig.HomeCard.SEND),
            home.order,
        )
        assertNull("the plan turned it off", home.poweredBy)
        assertEquals(MessengerConfig.HeaderStyle.IMAGE, home.header.style)
        assertEquals("https://app.clomni.ai/v1/images/head", home.header.imageUrl)
        assertTrue(home.header.glow)
        assertEquals("https://app.clomni.ai/v1/images/logo-dark", home.header.logoDarkUrl)
        assertEquals("team.show false", emptyList<String>(), home.header.teamAvatars)
        assertEquals("Xoş gəldin, Aysel!", home.header.greeting)
        assertEquals("Sualınız var?", home.header.title)
        assertEquals("Yazın", home.newConversation?.title)
        assertEquals("the office is closed", "Səhər cavab veririk", home.newConversation?.subtitle)
        assertEquals("no bot picture: the brand's logo", "https://app.clomni.ai/v1/images/logo", HomePresenter.botAvatar(config))

        // Without a recent conversation, that card is not in the order at all.
        assertEquals(listOf(MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.CHANNELS, MessengerConfig.HomeCard.SEND), presenter(config = config).home(snapshot(config)).order)
        // A picture style without its picture is the gradient; solid stays solid.
        val noPicture = ProtocolJson().parseConfig("""{"brand":{"header_style":"image"}}""")!!
        assertEquals(MessengerConfig.HeaderStyle.GRADIENT, presenter(config = noPicture).home(snapshot(noPicture)).header.style)
        val solid = ProtocolJson().parseConfig("""{"brand":{"header_style":"solid"}}""")!!
        assertEquals(MessengerConfig.HeaderStyle.SOLID, presenter(config = solid).home(snapshot(solid)).header.style)
    }

    /** A bot's message on Home shows the panel's bot picture, as the conversation does. */
    @Test
    fun theBotsPictureIsThePanels() {
        val bot = listOf(Fixture.conversation("conv_1", "01-text-bot.json"))
        val panel = Fixture.exampleConfig.let { it.copy(bot = it.bot.copy(avatarUrl = "https://app.clomni.ai/v1/images/bot")) }
        assertEquals("https://app.clomni.ai/v1/images/bot", presenter(config = panel).home(snapshot(panel, bot)).recent?.row?.avatarUrl)
        val none = ProtocolJson().parseConfig("""{"brand":{"name":"Example","logo_url":"https://app.clomni.ai/v1/images/logo"}}""")!!
        assertEquals("the message's own", "https://app.clomni.ai/a/bot.png", presenter(config = none).home(snapshot(none, bot)).recent?.row?.avatarUrl)
    }

    /** CM-114: at most three news cards, in the panel's order; none without news; the item's screen. */
    @Test
    fun news() {
        val items = ProtocolJson().parseNews(ProtocolFiles.read("fixtures/61-news.json"))!!
        assertEquals(listOf("news_12", "news_9"), items.map { it.id })
        val home = presenter().home(snapshot(Fixture.exampleConfig).copy(news = items + items + items))
        assertEquals(3, home.news.size)
        assertTrue(MessengerConfig.HomeCard.NEWS in home.order)
        assertFalse("no news, no card", MessengerConfig.HomeCard.NEWS in presenter().home(snapshot(Fixture.exampleConfig)).order)
        val screen = presenter().news(snapshot(Fixture.exampleConfig).copy(news = items), "news_12")!!
        assertEquals("Yeni zonalar açıldı", screen.title)
        assertEquals(NewsItem.Button("Xəritəni aç", "myapp://map/zones"), screen.button)
        assertEquals(listOf(false, true, true, false), screen.blocks.map { it.bullet })
        assertEquals("40 yeni zona", screen.blocks.first().runs.single { it.bold }.text)
        assertEquals("2 oktyabr 09:00", screen.date)
        assertNull("withdrawn", presenter().news(snapshot(Fixture.exampleConfig), "news_12"))
    }

    @Test
    fun recentMessageIsHiddenWithoutAConversation() {
        assertNull(presenter().home(snapshot(Fixture.exampleConfig, emptyList())).recent)
        val empty = Fixture.conversation("conv_new", null)
        assertNull("nothing written in it yet", presenter().home(snapshot(Fixture.exampleConfig, listOf(empty))).recent)
    }

    @Test
    fun recentMessageRow() {
        val fromOperator = Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 2)
        val row = presenter().home(snapshot(Fixture.exampleConfig, listOf(fromOperator))).recent!!.row
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

        // The user wrote last: "Siz", and the user's own initial; the operator's face was beside it (test report).
        val fromUser = Fixture.conversation("conv_2", "03-text-user.json", assignee = "Rauf", at = "2026-10-01T10:31:50Z")
        val mine = presenter().row(fromUser, Fixture.exampleConfig)!!
        assertEquals("Siz · indi", mine.detail)
        assertEquals("S", mine.initial)
        assertNull("not the operator's picture", mine.avatarUrl)
        assertFalse(mine.unread)
        assertFalse(mine.accessibilityLabel.contains("Oxunmamış"))
        assertEquals("the logged-in user's initial", "A", presenter().row(fromUser, Fixture.exampleConfig, "Aysel Məmmədova")!!.initial)
        val card = presenter().home(snapshot(Fixture.exampleConfig, listOf(fromUser)).copy(userName = "Aysel")).recent!!.row
        assertNull("Home's card the same", card.avatarUrl)
        assertEquals("A", card.initial)

        // A bot's quick replies: its fallback text on one line, the bot's name and avatar.
        val fromBot = Fixture.conversation("conv_3", "10-example-level2-S-chips.json")
        val bot = presenter().row(fromBot, Fixture.exampleConfig)!!
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
        assertEquals("Leyla · 2 dəq", presenter().row(nameless, Fixture.exampleConfig)!!.detail)
        assertEquals("C", presenter(config = null).row(Fixture.conversation("conv_6", "01-text-bot.json"), null)!!.initial)
    }

    @Test
    fun markdownIsRemovedFromPreviews() {
        fun preview(text: String) = HomePresenter.plainText(
            Message("msg_1", null, "conv_1", "text", Sender(SenderType.BOT), now, 1, "az", null, MessageContent.Text(text), text),
        )
        assertEquals("Salam! Xoş gəldiniz şərtlər 2*3", preview("**Salam!** *Xoş* gəldiniz\n\n[şərtlər](https://example.com) 2*3"))
        assertEquals("👍🙏", preview("👍🙏"))
        // A letter of the alphabet before "*" is a word character on every platform.
        assertEquals("ə*x*", preview("ə*x*"))
    }

    @Test
    fun messagesCardDot() {
        val list = listOf(Fixture.conversation("conv_1", "02-text-operator-markdown.json"))
        val quiet = snapshot(Fixture.exampleConfig, list)
        assertFalse(presenter().home(quiet).messagesCard.unread)
        assertEquals("Mesajlar", presenter().home(quiet).messagesCard.accessibilityLabel)
        val card = presenter().home(quiet.copy(unreadTotal = 1)).messagesCard
        assertTrue(card.unread)
        assertEquals("Mesajlar", card.title)
        assertEquals("Mesajlar, Oxunmamış mesaj var", card.accessibilityLabel)
        val unreadInList = snapshot(Fixture.exampleConfig, listOf(Fixture.conversation("conv_1", "02-text-operator-markdown.json", unread = 1)))
        assertTrue("before the first unread.changed", presenter().home(unreadInList).messagesCard.unread)
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
        assertEquals("İnternet yoxdur", home.offline)
        assertEquals(home.offline, presenter().messages(cached).offline)
        assertEquals("the capsule's word once it is back", "Qoşuldu", home.connected)
        assertEquals(home.connected, presenter().messages(cached).connected)
    }

    /** CM-077: the capsule says "İnternet yoxdur", then "Qoşuldu" for a second once it is back, then goes. */
    @Test
    fun theOfflineCapsulesStates() {
        assertEquals(OfflineNotice.HIDDEN, OfflineNotice.HIDDEN.next(offline = false))
        val offline = OfflineNotice.HIDDEN.next(offline = true)
        assertEquals(OfflineNotice.OFFLINE, offline)
        val back = offline.next(offline = false)
        assertEquals(OfflineNotice.BACK, back)
        assertEquals("gone after its second", OfflineNotice.HIDDEN, back.expired())
        assertEquals("offline again before the second is up", OfflineNotice.OFFLINE, back.next(offline = true))
        assertEquals("the second does not close it then", OfflineNotice.OFFLINE, back.next(offline = true).expired())
        assertEquals(1_000L, OfflineNotice.BACK_MS)
    }

    @Test
    fun messagesTab() {
        val list = listOf(
            Fixture.conversation("conv_2", "03-text-user.json"),
            Fixture.conversation("conv_new", null),
            Fixture.conversation("conv_1", "02-text-operator-markdown.json"),
        )
        val messages = presenter().messages(snapshot(Fixture.exampleConfig, list))
        assertEquals("Mesajlar", messages.title)
        assertEquals(HomeScreen.Phase.READY, messages.phase)
        assertEquals(listOf("conv_2", "conv_1"), messages.rows.map { it.id })
        assertNull(messages.empty)
        assertEquals("Bizə mesaj göndərin", messages.newConversation.title)

        val empty = presenter().messages(snapshot(Fixture.exampleConfig, emptyList()))
        assertEquals("Hələ söhbət yoxdur", empty.empty)
        assertEquals(HomeScreen.Phase.READY, empty.phase)
        assertNull(empty.failure)

        val stale = snapshot(Fixture.exampleConfig, list).copy(conversationsLoad = MessengerSnapshot.Load.FAILED)
        assertEquals("the cached list stays", HomeScreen.Phase.READY, presenter().messages(stale).phase)
        // The SDK's own Russian (fixture 42's texts are the Azerbaijani set the server sent).
        assertEquals("Пока нет переписки", presenter("ru", config = null).messages(snapshot(Fixture.exampleConfig, emptyList())).empty)
    }

    @Test
    fun channelStyles() {
        val strings = ClomniStrings("az")
        fun item(type: String, url: String) = ChannelItem.of(type, url, strings)
        assertEquals(ChannelItem.Icon.INSTAGRAM, item("instagram", "https://instagram.com/example").icon)
        assertEquals("its name for TalkBack", "Instagram", item("instagram", "https://instagram.com/example").accessibilityLabel)
        assertEquals(ChannelItem.Icon.WHATSAPP, item("WhatsApp", "https://wa.me/1").icon)
        assertEquals(ChannelItem.Icon.LINKEDIN, item("linkedin", "https://linkedin.com/x").icon)
        assertEquals(ChannelItem.Icon.EMAIL, item("email", "mailto:a@b.az").icon)
        assertEquals("a mailto: link is email", "E-poçt", item("support", "mailto:a@b.az").accessibilityLabel)
        assertEquals("Telefon", item("call", "tel:+994501234567").accessibilityLabel)
        assertEquals(ChannelItem.Icon.PHONE, item("call", "tel:+994501234567").icon)
        assertEquals(ChannelItem.Icon.X, item("twitter", "https://twitter.com/example").icon)
        val unknown = item("mastodon", "https://social.example/@example")
        assertEquals(ChannelItem.Icon.LINK, unknown.icon)
        assertEquals("social.example", unknown.accessibilityLabel)
        assertEquals("not a URL: the text itself", "nə isə", item("site", "nə isə").accessibilityLabel)
        assertNotEquals(item("instagram", "https://a").id, item("instagram", "https://b").id)
        val all = listOf("telegram", "facebook", "messenger", "youtube", "tiktok").map { item(it, "https://$it.com").icon }
        assertEquals(
            listOf(ChannelItem.Icon.TELEGRAM, ChannelItem.Icon.FACEBOOK, ChannelItem.Icon.MESSENGER, ChannelItem.Icon.YOUTUBE, ChannelItem.Icon.TIKTOK),
            all,
        )
    }
}
