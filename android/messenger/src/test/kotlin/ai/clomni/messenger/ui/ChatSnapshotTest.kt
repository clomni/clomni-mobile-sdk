package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatFixture
import ai.clomni.messenger.presentation.ChatItem
import ai.clomni.messenger.presentation.ChatPresenter
import ai.clomni.messenger.presentation.ChatScreen
import ai.clomni.messenger.presentation.ChatSnapshot
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.MessengerSnapshot
import ai.clomni.messenger.presentation.RatingCard
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import com.android.resources.Density
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** 2026-10-01T10:32Z: two minutes after most fixtures. */
private const val NOW = 1_790_850_720_000L

private fun present(snapshot: ChatSnapshot, now: Long = NOW) =
    ChatPresenter(ClomniStrings("az", snapshot.config?.strings.orEmpty()), TimeZone.getTimeZone("UTC"), now).screen(snapshot)

/**
 * Every message fixture of protocol/fixtures/index.json in the conversation screen, light and dark, the whole
 * conversation laid out (the picture is as tall as it is).
 */
class ChatFixtureSnapshotTest {
    private val semantics = SemanticsCapture()

    // Shrunk to the content, from a screen tall enough for the longest form: on the phone's own height the composer
    // was squeezed under it.
    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5.copy(screenHeight = 6000),
        theme = "android:Theme.Material.Light.NoActionBar",
        renderingMode = SessionParams.RenderingMode.SHRINK,
        renderExtensions = setOf(semantics),
    )

    @Test
    fun everyMessageFixture() {
        val protocol = ProtocolJson()
        val config = Fixture.aparConfig
        var rendered = 0
        for (entry in ProtocolFiles.index("fixtures")) {
            if (entry.schema != "message.json") continue
            // A message the parser drops (no seq, say) has nothing to show.
            val message = protocol.parseMessage(ProtocolFiles.read(entry.path)) ?: continue
            val answerable = if (message.flow?.interactive == true) setOf(message.id) else emptySet()
            val screen = present(
                ChatSnapshot(
                    config = config,
                    conversation = ChatFixture.botConversation(listOf(message), answerable).takeIf { answerable.isNotEmpty() },
                    messages = listOf(message),
                    answerable = answerable,
                    load = MessengerSnapshot.Load.LOADED,
                ),
            )
            val name = entry.path.removePrefix("fixtures/").removeSuffix(".json")
            for (dark in listOf(false, true)) {
                val theme = ClomniTheme.make(config.brand, dark)
                paparazzi.snapshot("$name-${if (dark) "dark" else "light"}") {
                    CompositionLocalProvider(LocalInspectionMode provides true) {
                        ChatScreenView(screen, theme, ChatActions(), lazy = false)
                    }
                }
                semantics.assertTouchTargets(name)
            }
            rendered++
        }
        assertTrue("$rendered", rendered >= 35)
    }
}

/** The conversation screen's states on a phone, as the app lays them out (brief 8·7.4, 7.5). */
class ChatSnapshotTest {
    private val semantics = SemanticsCapture()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_5,
        theme = "android:Theme.Material.Light.NoActionBar",
        renderExtensions = setOf(semantics),
    )

    private val protocol = ProtocolJson()

    private fun snap(
        name: String,
        snapshot: ChatSnapshot,
        dark: Boolean = false,
        now: Long = NOW,
        draft: String = "",
        safeAreas: Boolean = false,
    ) {
        val screen = present(snapshot, now)
        val theme = ClomniTheme.make(snapshot.config?.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                Scene(theme, safeAreas) { ChatScreenView(screen, theme, ChatActions(), draft = draft) }
            }
        }
        semantics.assertTouchTargets(name)
    }

    /**
     * [safeAreas]: the reference phone's 46 dp status bar and 20 dp home indicator around the screen, so the comparison
     * pictures line up; Paparazzi draws neither.
     */
    @Composable
    private fun Scene(theme: ClomniTheme, safeAreas: Boolean, content: @Composable () -> Unit) {
        if (!safeAreas) return content()
        Column(Modifier.fillMaxSize().background(theme.colors.background.color)) {
            Spacer(Modifier.height(46.dp))
            Column(Modifier.weight(1f)) { content() }
            Spacer(Modifier.height(20.dp))
        }
    }

    private fun loaded(vararg messages: Message, answerable: Set<String> = emptySet()) = ChatSnapshot(
        config = Fixture.aparConfig,
        conversation = ChatFixture.botConversation(messages.toList(), answerable),
        messages = messages.toList(),
        answerable = answerable,
        load = MessengerSnapshot.Load.LOADED,
    )

    private val leyla = """{"name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png","online":true}"""

    /** A message of the reference's conversations. */
    private fun message(id: String, seq: Int, at: String, sender: String, type: String, content: String): Message =
        protocol.parseMessage(
            """{"id":"$id","conversation_id":"conv_5521","type":"$type","sender":$sender,"created_at":"2026-10-01T$at",
               "seq":$seq,"lang":"az","flow":${if (type == "quick_replies") """{"flow_id":"f","node_id":"n$seq","interactive":true}""" else "null"},
               "content":$content,"fallback_text":"-"}""",
        )!!

    private val bot = """{"type":"bot","id":"bot_default","name":"Clomni","avatar_url":"https://app.clomni.ai/a/bot.png"}"""
    private val user = """{"type":"user","id":"usr_1"}"""
    private val operator = """{"type":"operator","id":"op_42","name":"Leyla","avatar_url":"https://app.clomni.ai/a/leyla.png"}"""

    /** H2: "Yeni mesaj ↓" over the transcript's end while the user reads further up; a 48 dp target. */
    @Test
    fun newMessageCapsule() {
        for (dark in listOf(false, true)) {
            val theme = ClomniTheme.make(Fixture.aparConfig.brand, dark)
            val name = "chat_new_message_${if (dark) "dark" else "light"}"
            paparazzi.snapshot(name) {
                Box(Modifier.fillMaxWidth().height(96.dp).background(theme.colors.background.color)) {
                    NewMessageCapsule(true, "Yeni mesaj", theme, Modifier.align(Alignment.BottomCenter)) {}
                }
            }
            semantics.assertTouchTargets(name)
        }
    }

    @Test
    fun skeleton() = snap("chat_skeleton", ChatSnapshot(config = Fixture.aparConfig, conversation = ChatFixture.conversation("bot")))

    @Test
    fun loadFailedOffline() = snap(
        "chat_error_offline",
        ChatSnapshot(config = Fixture.aparConfig, load = MessengerSnapshot.Load.FAILED, isOffline = true),
    )

    @Test
    fun offline() {
        val offline = loaded(ChatFixture.message("01-text-bot.json")).copy(isOffline = true)
        snap("chat_offline", offline)
        snap("chat_offline_dark", offline, dark = true)
    }

    /** DESIGN-PASS-3 F2: answering the operator, the quote over the field; an earlier answer quoted in its bubble. */
    @Test
    fun replying() {
        val operator = ChatFixture.message("02-text-operator-markdown.json")
        val answer = ChatFixture.message("66-reply-user-to-operator.json", "seq" to 99)
        snap(
            "chat_replying",
            loaded(operator, answer).copy(conversation = ChatFixture.conversation("open", leyla), replyingTo = operator.id),
            draft = "Bəli",
        )
    }

    /**
     * A quoted text bubble is as wide as the wider of its quote and its text, the time at its bottom end; the text on
     * one line with the time beside it when the quote is the narrower. A bubble without a quote stays as it was.
     */
    @Test
    fun quotedTextWidths() {
        fun answer(id: String, seq: Int, sender: String, quoted: String, quoteAuthor: String, text: String) = protocol.parseMessage(
            """{"id":"$id","conversation_id":"conv_5521","type":"text","sender":$sender,"created_at":"2026-10-01T10:4$seq:00Z",
               "seq":$seq,"lang":"az","flow":null,"content":{"text":"$text"},"fallback_text":"-",
               "reply_to":{"id":"msg_q$seq","sender":{"type":"$quoteAuthor","name":"Leyla"},"excerpt":"$quoted","kind":"text"}}""",
        )!!
        snap(
            "chat_quoted_text_widths",
            loaded(
                answer("msg_q1", 1, user, "Ödənişi kartla etmisiniz, yoxsa balansdan? Qəbzin şəklini də göndərin.", "operator", "Kartla"),
                answer("msg_q2", 2, operator, "Bəli", "user", "Ödəniş tapıldı, pul qaytarıldı"),
                message("msg_q3", 3, "10:43:00Z", user, "text", """{"text":"Təşəkkür edirəm"}"""),
            ).copy(conversation = ChatFixture.conversation("open", leyla)),
        )
    }

    @Test
    fun closedConversation() = snap(
        "chat_closed",
        loaded(ChatFixture.message("03-text-user.json"), ChatFixture.message("24-system-conversation-closed.json"))
            .copy(conversation = ChatFixture.conversation("closed")),
    )

    /** input_disabled: the composer asks for a button, the step's chips with "← Geri". */
    @Test
    fun inputDisabled() {
        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        snap("chat_input_disabled", loaded(step, answerable = setOf(step.id)))
    }

    @Test
    fun operatorHeaderAndTyping() = snap(
        "chat_operator_typing",
        loaded(
            ChatFixture.message("03-text-user.json"),
            ChatFixture.message("23-system-operator-joined.json"),
            ChatFixture.message("31-operator-no-avatar.json", "created_at" to "2026-10-01T10:40:30Z"),
        ).copy(conversation = ChatFixture.conversation("open", leyla), typing = Sender(SenderType.OPERATOR, name = "Leyla")),
        now = 1_790_851_260_000L,
    )

    /**
     * A rating: open, a face chosen with the comment field open, and given (on its way); stars chosen. The chosen state
     * lives in the card, so that one is the card alone.
     */
    @Test
    fun ratings() {
        val rating = ChatFixture.message("28-rating.json", "created_at" to "2026-10-01T10:31:00Z")
        val given = PendingMessage("conv_5521", ClientMessage.RatingSubmit(rating.id, 5, "Tez cavab verdiniz"), null, NOW)
        val card = present(loaded(rating)).items.filterIsInstance<ChatItem.BubbleItem>().single().bubble.body as RatingCard
        for (dark in listOf(false, true)) {
            val look = if (dark) "dark" else "light"
            snap("chat_rating_open_$look", loaded(rating), dark)
            snapCard("chat_rating_chosen_$look", card, dark, chosen = 4)
            snap("chat_rating_given_$look", loaded(rating).copy(pending = listOf(given)), dark)
        }
        val stars = card.copy(
            scale = MessageContent.RatingScale.STAR_5,
            labels = (1..5).map { "$it ulduz" },
            comment = MessageContent.RatingComment.HIDDEN,
        )
        snapCard("chat_rating_stars_light", stars, dark = false, chosen = 3)
    }

    private fun snapCard(name: String, card: RatingCard, dark: Boolean, chosen: Int?) {
        val theme = ClomniTheme.make(Fixture.aparConfig.brand, dark)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) {
                Box(Modifier.fillMaxSize().background(theme.colors.background.color).padding(16.dp)) {
                    Box(Modifier.width(300.dp)) { RatingCardView(card, theme, chosenAtStart = chosen) { _, _ -> } }
                }
            }
        }
        semantics.assertTouchTargets(name)
    }

    @Test
    fun failedToSend() {
        val failed = PendingMessage("conv_5521", ClientMessage.Text("Gedişim bitmədi"), "Gedişim bitmədi", NOW, PendingMessage.State.FAILED, 3)
        val sending = PendingMessage("conv_5521", ClientMessage.Text("Kömək edin"), "Kömək edin", NOW)
        snap("chat_failed", loaded(ChatFixture.message("01-text-bot.json")).copy(pending = listOf(failed, sending)))
    }

    @Test
    fun afterHours() {
        val config = Fixture.aparConfig.let {
            it.copy(team = it.team.copy(officeHours = it.team.officeHours?.copy(openNow = false, nextOpenAt = 1_790_917_200_000L)))
        }
        snap("chat_after_hours", loaded(ChatFixture.message("01-text-bot.json")).copy(config = config))
    }

    @Test
    fun formLiveDark() {
        val form = ChatFixture.message("19-form-contact.json")
        snap(
            "chat_form_dark",
            loaded(form, answerable = setOf(form.id)).copy(known = mapOf("name" to "Aysel Məmmədova")),
            dark = true,
        )
    }

    @Test
    fun fontScale200() {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 2f))
        val languages = ChatFixture.message("07-language-select.json")
        snap("chat_font_scale_200", loaded(languages, answerable = setOf(languages.id)))
    }

    /** Clomni.setTypeface: the app's font on every text (serif stands in; layoutlib has no bold serif to pick). */
    @Test
    fun appsTypeface() {
        ai.clomni.messenger.Clomni.setTypeface(android.graphics.Typeface.SERIF)
        try {
            val step = ChatFixture.message("10-apar-level2-S-chips.json")
            snap("chat_typeface", loaded(ChatFixture.message("02-text-operator-markdown.json"), step, answerable = setOf(step.id)))
        } finally {
            ai.clomni.messenger.Clomni.setTypeface(null)
        }
    }

    /**
     * A choice, frame by frame as the phone draws it (operator, 2026-10-06, pictures 85 and 87): the capsules folded
     * with the transcript held; the user's message at the end with the bot typing under it; the bot's answer where the
     * typing was, the typing row under it with the run's only avatar. Nothing lies over anything in any of them.
     */
    @Test
    fun aChoiceNeverOverlaps() {
        val greeting = message("m1", 1, "10:31:00Z", bot, "text", """{"text":"Salam! Nə ilə kömək edək?"}""")
        val menu = message(
            "m2", 2, "10:31:00Z", bot, "quick_replies",
            """{"layout":"vertical","input_disabled":true,
               "buttons":[{"id":"order","title":"Sifarişim haqqında","icon":null,"payload":"node:order"},
                          {"id":"pay","title":"Ödəniş","icon":null,"payload":"node:pay"},
                          {"id":"tech","title":"Texniki problem","icon":null,"payload":"node:tech"}]}""",
        )
        val waiting = loaded(greeting, menu, answerable = setOf("m2"))
        val buttons = (present(waiting).items.last() as ChatItem.RepliesItem).block.buttons.map { it.accessibilityLabel }
        val chosen = PendingMessage("conv_5521", ClientMessage.ButtonReply("m2", "tech", "node:tech"), "Texniki problem", NOW)
        val typing = Sender(SenderType.BOT)
        val answer = message("m4", 4, "10:31:50Z", bot, "text", """{"text":"Problemi qısaca yazın."}""")

        val held = present(waiting)
        frame("choice_1_folding", held, ChoiceFold().apply { start(held.items, "replies-m2") }) { found ->
            assertTrue("the capsules take no place: $found", found.none { it.label in buttons })
            assertEquals("the transcript held: no message of the user's yet", 1, found.size)
        }
        frame("choice_2_sent", present(loaded(greeting, menu).copy(pending = listOf(chosen), typing = typing))) { found ->
            assertEquals("bot, user, clock, typing: $found", listOf("Apar bot", "Siz", "Göndərilir", "Apar yazır"), found.map { it.label.substringBefore(",") })
        }
        val sent = message("m3", 3, "10:31:40Z", user, "text", """{"text":"Texniki problem"}""")
        val answered = present(loaded(greeting, menu, sent, answer).copy(typing = typing))
        val answerBubble = answered.items.filterIsInstance<ChatItem.BubbleItem>().last().bubble
        assertEquals("the typing row has the run's avatar", null, answerBubble.avatar)
        frame("choice_3_answered", answered) { found ->
            assertEquals("bot, user, ✓, bot, typing: $found", listOf("Apar bot", "Siz", "Göndərildi", "Apar bot", "Apar yazır"), found.map { it.label.substringBefore(",") })
        }
    }

    /** [screen] in the lazy transcript; [check] gets its messages, status and typing row, top to bottom, none over another. */
    private fun frame(name: String, screen: ChatScreen, fold: ChoiceFold = ChoiceFold(), check: (List<SemanticsCapture.Element>) -> Unit) {
        val theme = ClomniTheme.make(Fixture.aparConfig.brand, false)
        paparazzi.snapshot(name) {
            CompositionLocalProvider(LocalInspectionMode provides true) { ChatScreenView(screen, theme, ChatActions(), fold = fold) }
        }
        val labels = screen.items.flatMap { item ->
            when (item) {
                is ChatItem.BubbleItem -> listOfNotNull(item.bubble.accessibilityLabel, item.bubble.status?.text)
                is ChatItem.RepliesItem -> item.block.buttons.map { it.accessibilityLabel }
                is ChatItem.TypingItem -> listOf(item.line.accessibilityLabel)
                else -> emptyList()
            }
        }.toSet()
        val found = semantics.elements.filter { it.label in labels }.sortedBy { it.top }
        for ((i, a) in found.withIndex()) {
            for (b in found.drop(i + 1)) {
                val apart = a.fromStart + a.width <= b.fromStart + 0.5f || b.fromStart + b.width <= a.fromStart + 0.5f ||
                    a.top + a.height <= b.top + 0.5f || b.top + b.height <= a.top + 0.5f
                assertTrue("$name: \"$a\" lies over \"$b\"", apart)
            }
        }
        check(found)
    }

    // The reference (docs/ui-reference.html 4.2, 4.3) at its own size, 282×602 dp at 1.5×, with its data.

    private fun reference() = paparazzi.unsafeUpdateConfig(
        deviceConfig = DeviceConfig.PIXEL_5.copy(screenWidth = 423, screenHeight = 903, xdpi = 240, ydpi = 240, density = Density.HIGH),
    )

    private fun languageChoice(): List<Message> = listOf(
        message("m1", 1, "10:30:00Z", bot, "text", """{"text":"Salam, Clomni-yə xoş gəlmisiniz. Zəhmət olmasa dil seçin."}"""),
        message(
            "m2", 2, "10:30:00Z", bot, "quick_replies",
            """{"text":"Please choose your language.\nПожалуйста, выберите язык.","layout":"vertical","input_disabled":false,
               "buttons":[{"id":"az","title":"Azərbaycan dili","icon":"🇦🇿","payload":"set_lang:az"},
                          {"id":"en","title":"English","icon":"🇬🇧","payload":"set_lang:en"},
                          {"id":"ru","title":"Русский","icon":"🇷🇺","payload":"set_lang:ru"}]}""",
        ),
    )

    /** 4.2, before the choice. */
    @Test
    fun referenceLanguageChoice() {
        reference()
        snap("reference_4_2_before", loaded(*languageChoice().toTypedArray(), answerable = setOf("m2")), now = 1_790_850_620_000L, safeAreas = true)
    }

    /** 4.2, after the choice: the choice as the user's message ("Göndərildi"), then the bot typing. */
    @Test
    fun referenceLanguageChosen() {
        reference()
        val chosen = message("m3", 3, "10:31:00Z", user, "text", """{"text":"🇦🇿 Azərbaycan dili"}""")
        snap(
            "reference_4_2_after",
            loaded(*(languageChoice() + chosen).toTypedArray()).copy(typing = Sender(SenderType.BOT)),
            now = 1_790_850_680_000L,
            safeAreas = true,
        )
    }

    /** 4.3, path S: chips with "← Geri", the composer locked. */
    @Test
    fun referenceFlowStep() {
        reference()
        val messages = listOf(
            message("m1", 1, "10:28:00Z", bot, "text", """{"text":"**Salam!** Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz."}"""),
            message("m2", 2, "10:28:00Z", bot, "text", """{"text":"Aşağıdakı başlıqlardan sizə uyğun olanı seçin."}"""),
            message("m3", 3, "10:29:40Z", user, "text", """{"text":"Aktiv gediş ilə bağlı problem yaşayıram"}"""),
            ChatFixture.message("10-apar-level2-S-chips.json", "seq" to 4, "created_at" to "2026-10-01T10:30:00Z"),
        )
        snap("reference_4_3_flow", loaded(*messages.toTypedArray(), answerable = setOf("msg_f10")), now = 1_790_850_620_000L, safeAreas = true)
    }

    /** 4.3, the operator: queue and join lines, Leyla's run, "Oxundu", a message being written. */
    @Test
    fun referenceOperator() {
        reference()
        // The bot's greeting is above the screen, as in the reference (its feed is scrolled to the end).
        val messages = listOf(
            message("m0", 1, "10:29:00Z", bot, "text", """{"text":"Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz."}"""),
            message("m1", 1, "10:30:00Z", user, "text", """{"text":"Gedişim bitmədi, pul çıxılmağa davam edir"}"""),
            message("m2", 2, "10:30:10Z", """{"type":"system"}""", "system", """{"event":"waiting_in_queue","text":"Sizi komandaya yönləndiririk"}"""),
            message("m3", 3, "10:30:40Z", """{"type":"system"}""", "system", """{"event":"operator_joined","text":"Leyla söhbətə qoşuldu"}"""),
            message("m4", 4, "10:31:00Z", operator, "text", """{"text":"Salam, Aysel. Gedişinizi yoxlayıram."}"""),
            message("m5", 5, "10:31:30Z", operator, "text", """{"text":"Gedişi bitirdim, balansınıza 2 AZN qaytarıldı."}"""),
            message("m6", 6, "10:31:50Z", user, "text", """{"text":"Çox sağ olun"}"""),
        )
        snap(
            "reference_4_3_operator",
            loaded(*messages.toTypedArray()).copy(conversation = ChatFixture.conversation("open", leyla), readUpTo = 6),
            now = 1_790_850_720_000L,
            draft = "Velosiped Nizami küçəsindədir",
            safeAreas = true,
        )
    }
}
