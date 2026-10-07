package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import ai.clomni.messenger.store.PendingUpload
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.TimeZone

/** Message fixtures for the conversation screen, with fields replaced. */
internal object ChatFixture {
    private val protocol = ProtocolJson()

    /** Fixture [name] with [changes] (`created_at`, `id`, `seq`, `content` …) as JSON values. */
    fun message(name: String, vararg changes: Pair<String, Any>): Message {
        val fields = Json.parseToJsonElement(ProtocolFiles.read("fixtures/$name")).jsonObject.toMutableMap()
        for ((key, value) in changes) fields[key] = json(value)
        return protocol.parseMessage(JsonObject(fields).toString()) ?: error(name)
    }

    /** A conversation in a given state, for the header; [assignee] and [flow] are JSON. */
    fun conversation(status: String, assignee: String = "null", id: String = "conv_5521", flow: String = "null"): Conversation =
        protocol.parseConversation(
            """{"id":"$id","status":"$status","assignee":$assignee,"flow":$flow,"created_at":"2026-10-01T10:00:00Z"}""",
        )!!

    /** A bot conversation whose flow waits on the buttons or the form of the [answerable] message, as the server says. */
    fun botConversation(messages: List<Message>, answerable: Set<String>): Conversation {
        val waiting = messages.lastOrNull { it.id in answerable }?.content ?: return conversation("bot")
        return conversation("bot", flow = flow(if (waiting is MessageContent.Form) "form" else "menu"))
    }

    /** conversation.flow while a flow drives the conversation and waits for [awaiting]. */
    fun flow(awaiting: String?) = """{"active":true,"awaiting":${awaiting?.let { "\"$it\"" }},"flow_id":"flw_1","node_id":"S"}"""

    fun config(json: String) = protocol.parseConfig(json)!!

    private fun json(value: Any): JsonElement = when (value) {
        is JsonElement -> value
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is List<*> -> kotlinx.serialization.json.JsonArray(value.map { json(it!!) })
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to json(v!!) })
        else -> error("$value")
    }
}

class ChatPresenterTest {
    /** 2026-10-01T10:32Z. */
    private val now = 1_790_850_720_000L
    private val utc = TimeZone.getTimeZone("UTC")

    private fun screen(messages: List<Message>, build: (ChatSnapshot) -> ChatSnapshot = { it }): ChatScreen {
        val snapshot = build(
            ChatSnapshot(
                config = Fixture.aparConfig,
                conversation = ChatFixture.conversation("bot"),
                messages = messages,
                load = MessengerSnapshot.Load.LOADED,
            ),
        )
        val strings = ClomniStrings("az", snapshot.config?.strings.orEmpty())
        return ChatPresenter(strings, utc, now).screen(snapshot)
    }

    private fun bubbles(screen: ChatScreen) = screen.items.filterIsInstance<ChatItem.BubbleItem>().map { it.bubble }

    private fun text(bubble: Bubble?) = (bubble?.body as? Bubble.TextBody)?.runs?.joinToString("") { it.text }

    private fun pending(content: ClientMessage, preview: String?, upload: PendingUpload? = null) =
        PendingMessage("conv_5521", content, preview, now, upload = upload)

    @Test
    fun aBotRunHasOneAvatarAndOneMeta() {
        val first = ChatFixture.message("01-text-bot.json", "id" to "msg_a", "seq" to 1, "created_at" to "2026-10-01T10:30:50Z")
        val second = ChatFixture.message(
            "01-text-bot.json", "id" to "msg_b", "seq" to 2, "created_at" to "2026-10-01T10:31:30Z",
            "content" to mapOf("text" to "İkinci"),
        )
        val later = ChatFixture.message(
            "01-text-bot.json", "id" to "msg_c", "seq" to 3, "created_at" to "2026-10-01T10:32:40Z",
            "content" to mapOf("text" to "Üçüncü"),
        )
        val list = bubbles(screen(listOf(first, second, later)))
        assertEquals(
            "70 s later starts a new run",
            listOf(Bubble.Position.FIRST, Bubble.Position.LAST, Bubble.Position.SINGLE),
            list.map { it.position },
        )
        assertNull(list[0].avatar)
        assertEquals("the author over the first of the run: the bot speaks as the brand", "Apar", list[0].author)
        assertNull(list[1].author)
        assertEquals("each bubble has its own clock inside it, no line under the run (G7)", listOf("10:30", "10:31", "10:32"), list.map { it.time })
        assertEquals("the bot is the company: its logo", ChatAvatar(Fixture.aparConfig.brand.logoUrl, "A", true), list[1].avatar)
        assertEquals(List(3) { Bubble.Side.INCOMING }, list.map { it.side })
        assertEquals("Apar bot, 10:30: Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz.", list[0].accessibilityLabel)
    }

    @Test
    fun timeSeparators() {
        val first = ChatFixture.message("01-text-bot.json", "created_at" to "2026-10-01T08:00:00Z")
        val near = ChatFixture.message("03-text-user.json", "created_at" to "2026-10-01T08:59:00Z")
        val far = ChatFixture.message("02-text-operator-markdown.json", "created_at" to "2026-10-01T10:30:00Z")
        val times = screen(listOf(first, near, far)).items.filterIsInstance<ChatItem.TimeItem>().map { it.text }
        assertEquals("after more than an hour, again", listOf("Bu gün 08:00", "Bu gün 10:30"), times)
        assertTrue("the first message has one", screen(listOf(first)).items.first() is ChatItem.TimeItem)
    }

    @Test
    fun operatorBubbleAndMarkdown() {
        val reply = bubbles(
            screen(listOf(ChatFixture.message("02-text-operator-markdown.json", "created_at" to "2026-10-01T10:30:00Z"))),
        ).first()
        assertEquals("Leyla", reply.author)
        assertEquals("10:30", reply.time)
        assertEquals("L", reply.avatar?.initial)
        val runs = (reply.body as Bubble.TextBody).runs
        assertEquals(TextRun("Gedişinizi yoxladıq.", bold = true), runs.first())
        assertEquals("https://apar.az/sertler", runs.last().link)
        assertEquals("Leyla, 10:30: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı.\nƏtraflı: şərtlər", reply.accessibilityLabel)
    }

    @Test
    fun everyMessageOfTheUserHasItsStatus() {
        val mine = ChatFixture.message("03-text-user.json")
        assertEquals("Göndərildi", bubbles(screen(listOf(mine))).last().status?.text)
        assertEquals("Oxundu", bubbles(screen(listOf(mine)) { it.copy(readUpTo = 3) }).last().status?.text)
        assertEquals("Göndərildi", bubbles(screen(listOf(mine)) { it.copy(readUpTo = 2) }).last().status?.text)
        // A bot message after it: the user's keeps its mark (G7, as WhatsApp); the bot's has none.
        val answer = ChatFixture.message("01-text-bot.json", "seq" to 4, "created_at" to "2026-10-01T10:36:00Z")
        assertEquals(Bubble.Status.Mark.SENT, bubbles(screen(listOf(mine, answer))).first().status?.mark)
        assertNull(bubbles(screen(listOf(mine, answer))).last().status)
        val alone = bubbles(screen(listOf(mine))).last()
        assertEquals(Bubble.Side.OUTGOING, alone.side)
        assertNull(alone.avatar)
    }

    /** No words on the user's message: its time and the clock, then ✓, inside the bubble; the words are TalkBack's (G7). */
    @Test
    fun statusIsAMarkWithTheTime() {
        val sending = pending(ClientMessage.Text("Salam"), "Salam")
        val goes = bubbles(screen(emptyList()) { it.copy(pending = listOf(sending)) }).single()
        assertEquals(Bubble.Status("Göndərilir", false, null, Bubble.Status.Mark.SENDING), goes.status)
        assertEquals("the clock, not \"indi\"", "10:32", goes.time)
        val mine = ChatFixture.message("03-text-user.json", "created_at" to "2026-10-01T10:30:00Z")
        assertEquals(Bubble.Status("Göndərildi", false, null, Bubble.Status.Mark.SENT), bubbles(screen(listOf(mine))).single().status)
        assertEquals("10:30", bubbles(screen(listOf(mine))).single().time)
        assertEquals(Bubble.Status.Mark.READ, bubbles(screen(listOf(mine)) { it.copy(readUpTo = 3) }).single().status?.mark)
        val failed = sending.copy(state = PendingMessage.State.FAILED)
        assertNull("a failure is in words", bubbles(screen(emptyList()) { it.copy(pending = listOf(failed)) }).single().status?.mark)
    }

    /** The typing row: one avatar, at the end; none while the flow waits for a choice (operator, 2026-10-06). */
    @Test
    fun typingRowTakesTheAvatarAndWaitsForNoChoice() {
        val bot = ChatFixture.message("01-text-bot.json", "created_at" to "2026-10-01T10:31:30Z")
        val botTyping = screen(listOf(bot)) { it.copy(typing = Sender(SenderType.BOT, "bot_other")) }
        assertTrue(botTyping.items.last() is ChatItem.TypingItem)
        assertNull("the bot's run gives its avatar to the typing row", bubbles(botTyping).single().avatar)
        assertEquals("10:31", bubbles(botTyping).single().time)
        val leylaTyping = screen(listOf(bot)) { it.copy(typing = Sender(SenderType.OPERATOR, name = "Leyla")) }
        assertNotNull("someone else typing: the bot keeps its own", bubbles(leylaTyping).single().avatar)

        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        val waiting: (ChatSnapshot) -> ChatSnapshot = {
            it.copy(
                conversation = ChatFixture.conversation("bot", flow = ChatFixture.flow("menu")),
                answerable = setOf(step.id),
                typing = Sender(SenderType.BOT),
            )
        }
        assertTrue("choices wait: nobody is typing", screen(listOf(step), waiting).items.none { it is ChatItem.TypingItem })
        val tapped = screen(listOf(step)) { waiting(it).copy(pending = listOf(pending(ClientMessage.Text("A"), "A"))) }
        assertTrue("once chosen, the bot may type", tapped.items.last() is ChatItem.TypingItem)
        val over = screen(listOf(step)) { waiting(it).copy(conversation = ChatFixture.conversation("bot", flow = ChatFixture.flow(null))) }
        assertTrue("the flow waits for nothing", over.items.last() is ChatItem.TypingItem)
        val old = screen(listOf(step)) { waiting(it).copy(answerable = emptySet()) }
        assertTrue("the choices are not live", old.items.last() is ChatItem.TypingItem)
    }

    /** The user's message is one item from the moment it is written: the server's copy changes only its status. */
    @Test
    fun aSentMessageKeepsItsPlaceInTheTranscript() {
        val sending = pending(ClientMessage.Text("Gedişim bitmədi"), "Gedişim bitmədi")
        val before = bubbles(screen(emptyList()) { it.copy(pending = listOf(sending)) }).single()
        val confirmed = ChatFixture.message("03-text-user.json", "client_id" to sending.id)
        val after = bubbles(screen(listOf(confirmed))).single()
        assertEquals("the same key", before.id, after.id)
        assertEquals("Göndərilir", before.status?.text)
        assertEquals("Göndərildi", after.status?.text)
        val bot = ChatFixture.message("01-text-bot.json")
        assertEquals("without a client_id, its id", bot.id, bubbles(screen(listOf(bot))).single().id)
    }

    @Test
    fun pendingMessages() {
        val mine = ChatFixture.message("03-text-user.json", "created_at" to "2026-10-01T10:31:30Z")
        val sending = pending(ClientMessage.Text("Hələ yoldadır"), "Hələ yoldadır")
        val list = bubbles(screen(listOf(mine)) { it.copy(pending = listOf(sending)) })
        assertEquals("every message of the user has its mark (G7)", Bubble.Status.Mark.SENT, list[0].status?.mark)
        assertEquals("Hələ yoldadır", text(list[1]))
        assertEquals("Göndərilir", list[1].status?.text)
        assertEquals(
            "the user's messages a minute apart form a run",
            listOf(Bubble.Position.FIRST, Bubble.Position.LAST),
            list.map { it.position },
        )

        val failed = sending.copy(state = PendingMessage.State.FAILED)
        val back = pending(ClientMessage.back("msg_f10"), null)
        val form = pending(ClientMessage.FormSubmit("msg_f19", "frm_contact", emptyMap()), null)
        val withFailure = bubbles(screen(emptyList()) { it.copy(pending = listOf(failed, back, form)) })
        assertEquals("a submitted form has no bubble of its own", 2, withFailure.size)
        assertEquals(Bubble.Status("Göndərilmədi · Yenidən cəhd et", true, failed.id), withFailure[0].status)
        assertEquals("← Geri", text(withFailure[1]))
        assertEquals("Göndərilir", withFailure[1].status?.text)
        assertEquals("Siz, 10:32: ← Geri", withFailure[1].accessibilityLabel)
    }

    @Test
    fun pendingAttachments() {
        val photo = pending(
            ClientMessage.Attachment("", "Velosiped"),
            "Velosiped",
            PendingUpload("velo.jpg", "image/jpeg", 1_000, "upload-1"),
        )
        val pdf = pending(ClientMessage.Attachment("", null), null, PendingUpload("qaime.pdf", "application/pdf", 182_340, "upload-2"))
        val bare = pending(ClientMessage.Attachment("upl_7", "Yalnız mətn"), "Yalnız mətn")
        val file = File("/tmp/upload-1")
        val list = bubbles(screen(emptyList()) { it.copy(pending = listOf(photo, pdf, bare), localFiles = mapOf(photo.id to file)) })
        val image = list[0].body as Bubble.ImageBody
        assertEquals(file, image.localFile)
        assertEquals(listOf(TextRun("Velosiped")), image.caption)
        assertFalse(image.sizeKnown)
        assertEquals(Bubble.FileBody("qaime.pdf", "182 KB", Media.FileIcon.PDF, null), list[1].body)
        assertEquals("Siz, 10:32: qaime.pdf", list[1].accessibilityLabel)
        assertEquals("an attachment the app uploaded itself shows its caption", "Yalnız mətn", text(list[2]))
    }

    @Test
    fun header() {
        val bot = screen(emptyList()).header
        val logo = ChatHeader.Lead.Brand(ChatAvatar(Fixture.aparConfig.brand.logoUrl, "A", true))
        assertEquals("no operator: the company's logo, never a person's face", logo, bot.lead)
        assertEquals("Apar", bot.title)
        assertEquals("Adətən bir neçə dəqiqəyə cavab veririk", bot.subtitle)
        assertEquals("Geri", bot.backLabel)
        assertEquals("Bağla", bot.closeLabel)

        val queued = screen(emptyList()) { it.copy(conversation = ChatFixture.conversation("queued")) }.header
        assertEquals("Adətən bir neçə dəqiqəyə cavab veririk", queued.subtitle)

        val leyla = """{"name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png","online":true}"""
        val open = screen(emptyList()) { it.copy(conversation = ChatFixture.conversation("open", leyla)) }.header
        assertEquals(ChatHeader.Lead.Person(ChatAvatar("https://app.clomni.ai/a/leyla.png", "L", false), true), open.lead)
        assertEquals("Leyla", open.title)
        assertEquals("only the company: online is the dot", "Apar", open.subtitle)

        val away = """{"name":"Leyla","online":false}"""
        assertEquals("Apar", screen(emptyList()) { it.copy(conversation = ChatFixture.conversation("open", away)) }.header.subtitle)
        val queuedWithLeyla = screen(emptyList()) { it.copy(conversation = ChatFixture.conversation("queued", leyla)) }.header
        assertEquals("the assignee whatever the status", "Leyla", queuedWithLeyla.title)

        // Nobody assigned: the last operator who wrote, with no online dot; a bot's message after it changes nothing.
        val wrote = listOf(
            ChatFixture.message("02-text-operator-markdown.json", "id" to "m1", "seq" to 1),
            ChatFixture.message("01-text-bot.json", "id" to "m2", "seq" to 2),
        )
        val unassigned = screen(wrote) { it.copy(conversation = ChatFixture.conversation("queued")) }.header
        assertEquals(ChatHeader.Lead.Person(ChatAvatar("https://app.clomni.ai/a/leyla.png", "L", false), false), unassigned.lead)
        assertEquals("Leyla", unassigned.title)
        assertEquals("Apar", unassigned.subtitle)
        val rauf = """{"name":"Rauf","online":true}"""
        val assigned = screen(wrote) { it.copy(conversation = ChatFixture.conversation("open", rauf)) }.header
        assertEquals("the assignee before the last writer", "Rauf", assigned.title)
        assertEquals("only the bot wrote: the company", logo, screen(wrote.drop(1)).header.lead)

        val closedHours = ChatFixture.config(
            """{"brand":{"name":"Apar","primary_color":"#1F9D63"},"team":{"office_hours":{"open_now":false},"reply_time":"Tez"}}""",
        )
        val afterHours = screen(emptyList()) {
            it.copy(config = closedHours, conversation = ChatFixture.conversation("queued"))
        }.header
        assertEquals("no next_open_at: just that it is closed", "Hazırda iş saatı deyil", afterHours.subtitle)
        assertEquals(ChatHeader.Lead.Brand(ChatAvatar(null, "A", true)), afterHours.lead)

        val nextOpen = ChatFixture.config(
            """{"brand":{"name":"Apar","primary_color":"#1F9D63"},
               "team":{"office_hours":{"open_now":false,"next_open_at":"2026-10-02T05:00:00Z"}}}""",
        )
        assertEquals(
            "local time (these tests run in UTC), tomorrow",
            "Növbəti iş saatı: sabah 05:00",
            screen(emptyList()) { it.copy(config = nextOpen) }.header.subtitle,
        )
        val hidden = Fixture.aparConfig.let { it.copy(team = it.team.copy(show = false)) }
        assertEquals(logo, screen(emptyList()) { it.copy(config = hidden) }.header.lead)
    }

    @Test
    fun quickReplies() {
        val languages = ChatFixture.message("07-language-select.json")
        val open = screen(listOf(languages)) { it.copy(answerable = setOf(languages.id)) }
        val block = (open.items.last() as ChatItem.RepliesItem).block
        assertEquals(listOf("🇦🇿 Azərbaycan dili", "🇬🇧 English", "🇷🇺 Русский"), block.buttons.map { it.title })
        assertEquals(listOf("az", "en", "ru"), block.buttons.map { it.id })
        assertEquals("the role says \"button\" itself", "Azərbaycan dili, 1-ci, cəmi 3", block.buttons[0].accessibilityLabel)
        assertEquals(MessageContent.QuickRepliesLayout.VERTICAL, block.layout)
        assertNull(block.back)
        assertTrue(text(bubbles(open).first())!!.startsWith("Salam, Clomni-yə"))
        assertEquals("replies-msg_f07", open.items.last().id)

        // Answered (fixture 08): the buttons are gone, the text stays.
        val answered = screen(listOf(ChatFixture.message("08-language-select-answered.json")))
        assertTrue(answered.items.none { it is ChatItem.RepliesItem })
        assertEquals(1, bubbles(answered).size)

        // The composer goes by conversation.flow alone (operator, 2026-10-05).
        fun mode(flow: String, messages: List<Message> = listOf(languages)) =
            screen(messages) { it.copy(conversation = ChatFixture.conversation("bot", flow = flow), answerable = setOf(languages.id)) }.composer.mode
        assertEquals("a menu", ChatComposer.Mode.Hidden, mode(ChatFixture.flow("menu")))
        assertEquals("a form", ChatComposer.Mode.Hidden, mode(ChatFixture.flow("form")))
        assertEquals("a wait step: its next step follows", ChatComposer.Mode.Hidden, mode(ChatFixture.flow(null)))
        assertEquals("a value this SDK does not know is not text", ChatComposer.Mode.Hidden, mode(ChatFixture.flow("buttons")))
        assertEquals("a question answered in words", ChatComposer.Mode.Open, mode(ChatFixture.flow("text")))
        assertEquals("ended, stopped or handed over", ChatComposer.Mode.Open, mode("""{"active":false,"awaiting":null}"""))
        assertEquals("no flow sent (an older server): open", ChatComposer.Mode.Open, mode("null"))
        assertEquals("the earlier form reads as none", ChatComposer.Mode.Open, mode("""{"flow_id":"flw_1","node_id":"S"}"""))

        // Apar S: chips, the back button, no composer.
        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        val chips = screen(listOf(step)) { it.copy(answerable = setOf(step.id)) }
        val chipsBlock = (chips.items.last() as ChatItem.RepliesItem).block
        assertEquals(MessageContent.QuickRepliesLayout.CHIPS, chipsBlock.layout)
        assertEquals(ReplyButton("back", "← Geri", "Geri"), chipsBlock.back)

        // 13: the long title whole (the view wraps it to two lines); 14: ten buttons; 15: buttons without text.
        val long = ChatFixture.message("13-button-title-over-80.json")
        val longBlock = (screen(listOf(long)) { it.copy(answerable = setOf(long.id)) }.items.last() as ChatItem.RepliesItem).block
        assertEquals(112, longBlock.buttons[0].title.length)
        val ten = ChatFixture.message("14-ten-buttons.json")
        val tenBlock = (screen(listOf(ten)) { it.copy(answerable = setOf(ten.id)) }.items.last() as ChatItem.RepliesItem).block
        assertEquals(10, tenBlock.buttons.size)
        assertEquals("Variant 10, 10-cu, cəmi 10", tenBlock.buttons[9].accessibilityLabel)
        val bare = ChatFixture.message("15-quick-replies-no-text.json")
        val bareScreen = screen(listOf(bare)) { it.copy(answerable = setOf(bare.id)) }
        assertTrue("no text, no bubble", bubbles(bareScreen).isEmpty())
    }

    @Test
    fun theFlowsOwnRestartButtonLeavesNoSecondBack() {
        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        val withBack = (screen(listOf(step)) { it.copy(answerable = setOf(step.id)) }.items.last() as ChatItem.RepliesItem).block
        assertEquals("← Geri", withBack.back?.title)
        val restart = ChatFixture.message(
            "10-apar-level2-S-chips.json",
            "content" to mapOf(
                "text" to "Seçin",
                "allow_back" to true,
                "buttons" to listOf(mapOf("id" to "a", "title" to "Kart", "payload" to "a"), mapOf("id" to "r", "title" to "↺ Yenidən başla", "payload" to "r")),
            ),
        )
        val block = (screen(listOf(restart)) { it.copy(answerable = setOf(restart.id)) }.items.last() as ChatItem.RepliesItem).block
        assertNull(block.back)
    }

    @Test
    fun anOptionalFieldSaysSo() {
        val form = ChatFixture.message("19-form-contact.json")
        val card = bubbles(screen(listOf(form)) { it.copy(answerable = setOf(form.id)) }).first().body as FormCard
        val labels = card.fields.map { it.shownLabel }
        assertTrue(labels.any { it.endsWith(" (istəyə görə)") })
        assertTrue("a required field has no mark", card.fields.filter { it.required }.all { it.shownLabel == it.label })
    }

    @Test
    fun forms() {
        val contact = ChatFixture.message("19-form-contact.json")
        val live = screen(listOf(contact)) {
            it.copy(answerable = setOf(contact.id), known = mapOf("name" to "Aysel Məmmədova", "email" to "aysel@example.com"))
        }
        val card = bubbles(live).first().body as FormCard
        assertFalse(card.readOnly)
        assertEquals(listOf("name", "phone", "email"), card.fields.map { it.id })
        assertEquals(listOf("Aysel Məmmədova", "", "aysel@example.com"), card.fields.map { it.initialValue })
        assertEquals("Göndər", card.submitTitle)
        assertNull(card.sentLabel)
        assertEquals("Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.", card.text?.first()?.text)
        // TalkBack: who asks and when, then each field once, "*" said as a word.
        assertEquals("Apar bot, 10:30: Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.", card.textAccessibilityLabel)
        assertEquals(listOf("Ad, soyad, məcburi", "Telefon, məcburi", "Email"), card.fields.map { it.accessibilityLabel })

        val sent = bubbles(screen(listOf(ChatFixture.message("21-form-submitted.json")))).first().body as FormCard
        assertTrue(sent.readOnly)
        assertEquals("Göndərildi", sent.sentLabel)
        assertEquals(listOf("Aysel Məmmədova", "+994501234567", "aysel@example.com"), sent.submitted.map { it.value })

        val stale = bubbles(screen(listOf(contact))).first().body as FormCard
        assertTrue("no longer the live step", stale.readOnly)
        assertEquals(
            "Apar bot, 10:30: Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.",
            bubbles(screen(listOf(contact))).first().accessibilityLabel,
        )
    }

    @Test
    fun imagesAndFiles() {
        val image = bubbles(screen(listOf(ChatFixture.message("16-image.json")))).first().body as Bubble.ImageBody
        assertEquals("the thumbnail", "https://app.clomni.ai/f/velo_480.jpg", image.url)
        assertEquals("https://app.clomni.ai/f/velo.jpg", image.fullUrl)
        assertEquals(listOf(220.0, 165.0), listOf(image.width, image.height))
        assertTrue(image.sizeKnown)
        assertEquals(listOf(TextRun("Velosiped Nizami küçəsindədir")), image.caption)
        assertEquals(
            "Siz, 10:45: Şəkil: Velosiped Nizami küçəsindədir",
            bubbles(screen(listOf(ChatFixture.message("16-image.json")))).first().accessibilityLabel,
        )

        val unknown = bubbles(screen(listOf(ChatFixture.message("17-image-no-dimensions.json")))).first()
        val placeholder = unknown.body as Bubble.ImageBody
        assertFalse(placeholder.sizeKnown)
        assertEquals("https://app.clomni.ai/f/receipt.png", placeholder.url)
        assertEquals("Leyla, 10:46: Şəkil", unknown.accessibilityLabel)

        val file = bubbles(screen(listOf(ChatFixture.message("18-file-pdf.json")))).first()
        assertEquals(Bubble.FileBody("qaime.pdf", "182 KB", Media.FileIcon.PDF, "https://app.clomni.ai/f/qaime.pdf"), file.body)
        assertEquals("Leyla, 10:47: Fayl: qaime.pdf, 182 KB", file.accessibilityLabel)
    }

    @Test
    fun systemLinesAndFallbacks() {
        val leyla = """{"name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png"}"""
        val system = screen(
            listOf(
                "22-system-waiting-in-queue.json", "23-system-operator-joined.json", "24-system-conversation-closed.json",
                "25-system-unknown-event.json",
            ).map { ChatFixture.message(it) },
        ) { it.copy(conversation = ChatFixture.conversation("open", leyla)) }
        val lines = system.items.filterIsInstance<ChatItem.SystemItem>().map { it.line }
        assertEquals(
            listOf("Sizi operatora yönləndiririk", "Leyla söhbətə qoşuldu", "Söhbət bağlanıb", "Sizə qısa sorğu göndəriləcək"),
            lines.map { it.text },
        )
        assertEquals("the team waits with them", 3, lines[0].avatars.size)
        assertEquals("L", lines[1].avatars.first().initial)
        assertTrue(lines[2].avatars.isEmpty())
        assertTrue(bubbles(system).isEmpty())
        assertNull("a system line is not news", system.announcement)
        val nobody = screen(listOf(ChatFixture.message("23-system-operator-joined.json")))
        assertTrue(nobody.items.filterIsInstance<ChatItem.SystemItem>().single().line.avatars.isEmpty())

        // card, carousel and rating are phase 2: a 1.0 SDK shows their fallback text, like an unknown type.
        for ((file, fallback) in listOf(
            "26-card.json" to "Velosiped icarəsi: 30 dəq, 1 AZN. Ətraflı: https://apar.az",
            "27-carousel.json" to "Tarif 1 / Tarif 2 / Tarif 3",
            "28-rating.json" to "Xidmətimizi 1-5 qiymətləndirin",
            "29-unknown-type.json" to "Hansı saat uyğundur? 10:00 / 14:00",
        )) {
            val bubble = bubbles(screen(listOf(ChatFixture.message(file)))).first()
            assertEquals(file, fallback, text(bubble))
            assertEquals(file, Bubble.Side.INCOMING, bubble.side)
            assertTrue(file, bubble.accessibilityLabel.endsWith(fallback))
        }
    }

    @Test
    fun composer() {
        val open = screen(emptyList()).composer
        assertEquals(ChatComposer.Mode.Open, open.mode)
        assertEquals("Mesaj yazın…", open.placeholder)
        assertTrue(open.showsAttach && open.showsEmoji)
        assertEquals(4_000, open.limit)
        assertEquals("Göndər", open.sendLabel)
        assertEquals(
            listOf("Fayl əlavə et", "Şəkil və ya video", "Kamera", "Fayl", "Sil", "Emoji"),
            listOf(open.attachLabel, open.mediaLabel, open.cameraLabel, open.fileLabel, open.removeLabel, open.emojiLabel),
        )
        val closed = screen(emptyList()) { it.copy(conversation = ChatFixture.conversation("closed")) }.composer
        assertEquals(ChatComposer.Mode.Closed("Söhbət bağlanıb", "Yeni söhbət başlat"), closed.mode)
        val minimal = screen(emptyList()) { it.copy(config = Fixture.minimalConfig) }.composer
        assertEquals("the SDK's own text", "Mesaj yazın…", minimal.placeholder)
        val bare = screen(emptyList()) { it.copy(config = null) }
        assertEquals("Mesaj yazın…", bare.composer.placeholder)
        assertEquals("", bare.header.title)
        assertTrue(ChatPresenter.canSend(" Salam ", 10))
        assertFalse(ChatPresenter.canSend(" \n ", 10))
        assertFalse(ChatPresenter.canSend("12345678901", 10))
        assertTrue("emoji count once", ChatPresenter.canSend("👍👍👍", 3))
    }

    @Test
    fun typingStatesAndAnnouncement() {
        val operatorTyping = screen(listOf(ChatFixture.message("01-text-bot.json"))) {
            it.copy(typing = Sender(SenderType.OPERATOR, name = "Leyla"))
        }
        val line = (operatorTyping.items.last() as ChatItem.TypingItem).line
        assertEquals("Leyla yazır", line.accessibilityLabel)
        assertEquals("L", line.avatar.initial)
        assertEquals(
            Announcement("msg_f01", "Apar bot, 10:30: Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz."),
            operatorTyping.announcement,
        )
        assertNull("the user's own message is not news", screen(listOf(ChatFixture.message("03-text-user.json"))).announcement)
        val botTyping = screen(emptyList()) { it.copy(typing = Sender(SenderType.BOT)) }
        assertEquals("Apar yazır", (botTyping.items.single() as ChatItem.TypingItem).line.accessibilityLabel)
        val someone = screen(emptyList()) { it.copy(typing = Sender(SenderType.UNKNOWN)) }
        assertEquals("Apar yazır", (someone.items.single() as ChatItem.TypingItem).line.accessibilityLabel)

        val presenter = ChatPresenter(ClomniStrings("az"), utc, now)
        assertEquals(HomeScreen.Phase.LOADING, presenter.screen(ChatSnapshot()).phase)
        val failed = presenter.screen(ChatSnapshot(load = MessengerSnapshot.Load.FAILED, isOffline = true))
        assertEquals(HomeScreen.Phase.FAILED, failed.phase)
        assertEquals("Yenidən cəhd et", failed.failure?.retry)
        assertEquals("İnternet yoxdur", failed.offline)
        val cached = presenter.screen(ChatSnapshot(messages = listOf(ChatFixture.message("01-text-bot.json"))))
        assertEquals("what is cached shows while loading", HomeScreen.Phase.READY, cached.phase)
    }

    /** Every message fixture, valid or not, reaches the screen as something. */
    /** DESIGN-PASS-3 F2: the quote in the bubble, over the field, and who may be answered. */
    @Test
    fun replies() {
        fun quoteOf(file: String) = bubbles(screen(listOf(ChatFixture.message(file)))).single().quote
        assertEquals(
            Bubble.Quote("msg_f65", "Leyla", "Ödənişi kartla etmisiniz, yoxsa balansdan? Qəbzin şəklini də göndərə bilərsiniz, yoxlayaq."),
            quoteOf("66-reply-user-to-operator.json"),
        )
        assertEquals("the user's own message is \"Siz\"", Bubble.Quote("msg_f62", "Siz", "qebz.jpg"), quoteOf("67-reply-operator-to-image.json"))
        assertEquals(Bubble.Quote("msg_f60", "Siz", "Mesaj silinib"), quoteOf("68-reply-to-deleted.json"))
        assertNull("a broken reply_to: the message without its quote", quoteOf("70-invalid-reply-to-without-kind.json"))

        // Answering: the quote over the field; the user's message while it is on its way shows it too.
        val operator = ChatFixture.message("02-text-operator-markdown.json")
        val answering = screen(listOf(operator)) { it.copy(conversation = ChatFixture.conversation("open"), replyingTo = operator.id) }
        val quote = answering.composer.quote!!
        assertEquals(operator.id, quote.messageId)
        assertFalse("one line", quote.excerpt.contains('\n'))
        assertEquals("Bağla", answering.composer.cancelQuoteLabel)
        assertEquals(listOf("Cavabla", "Kopyala"), listOf(answering.replyLabel, answering.copyLabel))
        val bubble = bubbles(answering).single()
        assertTrue(bubble.replyable)
        assertEquals(operator.id, bubble.messageId)
        assertNotNull(bubble.copyText)
        val sending = screen(listOf(operator)) {
            it.copy(pending = listOf(pending(ClientMessage.Text("Bəli", replyTo = operator.id), "Bəli")))
        }
        val mine = bubbles(sending).last()
        assertEquals(quote, mine.quote)
        assertFalse("still on its way: nothing to answer yet", mine.replyable)
        assertEquals("Bəli", mine.copyText)

        // A flow waiting for a choice: no composer, so nothing is answered; copying still works.
        val menu = screen(listOf(operator)) {
            it.copy(conversation = ChatFixture.conversation("bot", flow = ChatFixture.flow("menu")), replyingTo = operator.id)
        }
        assertNull(menu.composer.quote)
        assertFalse(bubbles(menu).single().replyable)
        assertNotNull(bubbles(menu).single().copyText)
    }

    @Test
    fun everyMessageFixtureRenders() {
        val protocol = ProtocolJson()
        var rendered = 0
        for (entry in ProtocolFiles.index("fixtures")) {
            if (entry.schema != "message.json") continue
            val file = entry.path
            val message = protocol.parseMessage(ProtocolFiles.read(file)) ?: continue
            val chat = screen(listOf(message)) {
                it.copy(answerable = if (message.flow?.interactive == true) setOf(message.id) else emptySet())
            }
            assertFalse(file, chat.items.none { it !is ChatItem.TimeItem })
            rendered++
        }
        assertTrue("$rendered", rendered >= 35)
    }
}
