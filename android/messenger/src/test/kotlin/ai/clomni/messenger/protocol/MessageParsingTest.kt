package ai.clomni.messenger.protocol

import ai.clomni.messenger.protocol.MessageContent.Button
import ai.clomni.messenger.protocol.MessageContent.CardButton
import ai.clomni.messenger.protocol.MessageContent.CardItem
import ai.clomni.messenger.protocol.MessageContent.FormField
import ai.clomni.messenger.protocol.MessageContent.FormFieldType
import ai.clomni.messenger.protocol.MessageContent.QuickRepliesLayout
import ai.clomni.messenger.protocol.MessageContent.RatingComment
import ai.clomni.messenger.protocol.MessageContent.RatingScale
import ai.clomni.messenger.protocol.MessageContent.SystemEvent
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class MessageParsingTest {

    private val protocol = RecordingProtocol()

    private fun fixture(name: String): Message = protocol.json.parseMessage(ProtocolFiles.read("fixtures/$name"))!!

    private inline fun <reified T : MessageContent> content(name: String): T = fixture(name).content as T

    /** Fixture 01 with some envelope fields replaced; a null value removes the field. */
    private fun envelope(vararg changes: Pair<String, JsonElement?>): String {
        val fields = ProtocolFiles.json("fixtures/01-text-bot.json").jsonObject.toMutableMap()
        for ((key, value) in changes) if (value == null) fields.remove(key) else fields[key] = value
        return JsonObject(fields).toString()
    }

    private fun contentOf(type: String, content: String): MessageContent =
        protocol.json.parseContent(type, Json.parseToJsonElement(content))

    private fun assertUnknown(type: String, content: String) =
        assertEquals(content, MessageContent.Unknown::class, contentOf(type, content)::class)

    private fun assertLogged(fragment: String) =
        assertTrue("expected a log line with '$fragment', got ${protocol.warnings}", protocol.warnings.any { fragment in it })

    @Test
    fun envelopeOfABotMessage() {
        assertEquals(
            Message(
                id = "msg_f01",
                clientId = null,
                conversationId = "conv_5521",
                type = "text",
                sender = Sender(SenderType.BOT, "bot_default", "Clomni", "https://app.clomni.ai/a/bot.png"),
                createdAt = Instant.parse("2026-10-01T10:30:00Z").toEpochMilli(),
                seq = 1,
                lang = "az",
                flow = FlowRef("flw_example_az", "A0", 7, interactive = false),
                content = MessageContent.Text("Salam! Siz Example şirkətinin dəstək bölməsi ilə əlaqəyə keçmisiniz."),
                fallbackText = "Salam! Siz Example şirkətinin dəstək bölməsi ilə əlaqəyə keçmisiniz.",
            ),
            fixture("01-text-bot.json"),
        )
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun userMessageKeepsItsClientId() {
        val message = fixture("03-text-user.json")
        assertEquals("6f1c2c8e-1b2a-4c3d-8e9f-0a1b2c3d4e5f", message.clientId)
        assertEquals(Sender(SenderType.USER, "usr_12345", "Aysel Məmmədova", null), message.sender)
        assertNull(message.flow)
    }

    @Test
    fun textIsKeptAsSentForTheRenderer() {
        // Markdown and link filtering are the renderer's job; the protocol passes the text through.
        assertEquals(
            "**Gedişinizi yoxladıq.** Balansınıza *2 AZN* qaytarıldı.\nƏtraflı: [şərtlər](https://example.com/sertler)",
            content<MessageContent.Text>("02-text-operator-markdown.json").text,
        )
        assertEquals(
            "Bu linkə basmayın: [oyun](javascript:alert(1)) və [zəng](tel:+994501234567)",
            content<MessageContent.Text>("06-text-unsafe-link.json").text,
        )
        assertEquals("👍🙏", content<MessageContent.Text>("05-text-emoji-only.json").text)
    }

    @Test
    fun languageSelectionBeforeAndAfterTheChoice() {
        val before = fixture("07-language-select.json")
        assertEquals(
            listOf(
                Button("az", "Azərbaycan dili", "🇦🇿", "set_lang:az"),
                Button("en", "English", "🇬🇧", "set_lang:en"),
                Button("ru", "Русский", "🇷🇺", "set_lang:ru"),
            ),
            (before.content as MessageContent.QuickReplies).buttons,
        )
        assertEquals(true, before.flow?.interactive)
        val after = fixture("08-language-select-answered.json")
        assertEquals(before.id, after.id)
        assertEquals(false, after.flow?.interactive)
        assertEquals(before.content, after.content)
    }

    @Test
    fun exampleFlowLevels() {
        val level1 = content<MessageContent.QuickReplies>("09-example-level1-A.json")
        assertEquals(QuickRepliesLayout.VERTICAL, level1.layout)
        assertTrue(level1.inputDisabled)
        assertEquals(false, level1.allowBack)
        assertEquals(listOf("node:S", "node:R"), level1.buttons.map { it.payload })

        val level2 = content<MessageContent.QuickReplies>("10-example-level2-S-chips.json")
        assertEquals(QuickRepliesLayout.CHIPS, level2.layout)
        assertTrue(level2.allowBack)
        assertEquals(5, level2.buttons.size)

        assertEquals(
            listOf("handoff", "end"),
            content<MessageContent.QuickReplies>("12-example-level4-handoff.json").buttons.map { it.payload },
        )
        val end = fixture("50-example-end.json")
        assertEquals("END", end.flow?.nodeId)
        assertEquals(false, end.flow?.interactive)
    }

    @Test
    fun buttonTitleOver80IsKeptWhole() {
        val title = content<MessageContent.QuickReplies>("13-button-title-over-80.json").buttons[0].title
        assertEquals(
            "Gedişimi bitirdim, amma tətbiq hələ də gedişin davam etdiyini göstərir və balansımdan pul çıxılır, " +
                "nə etməliyəm?",
            title,
        )
        assertTrue(title.length > 80)
    }

    @Test
    fun tenButtonsAndButtonsWithoutText() {
        assertEquals(10, content<MessageContent.QuickReplies>("14-ten-buttons.json").buttons.size)
        assertEquals(
            MessageContent.QuickReplies(
                text = null,
                buttons = listOf(Button("o_ok", "Aydındır", null, "node:OK")),
                layout = QuickRepliesLayout.VERTICAL,
                inputDisabled = false,
                allowBack = false,
            ),
            content<MessageContent.QuickReplies>("15-quick-replies-no-text.json"),
        )
    }

    @Test
    fun imagesAndFiles() {
        assertEquals(
            MessageContent.Image(
                url = "https://app.clomni.ai/f/velo.jpg",
                thumbUrl = "https://app.clomni.ai/f/velo_480.jpg",
                width = 1280,
                height = 960,
                caption = "Velosiped Nizami küçəsindədir",
            ),
            content<MessageContent.Image>("16-image.json"),
        )
        assertEquals(
            MessageContent.Image("https://app.clomni.ai/f/receipt.png", null, null, null, null),
            content<MessageContent.Image>("17-image-no-dimensions.json"),
        )
        assertEquals(
            MessageContent.File("https://app.clomni.ai/f/qaime.pdf", "qaime.pdf", 182_340, "application/pdf"),
            content<MessageContent.File>("18-file-pdf.json"),
        )
    }

    @Test
    fun voiceMessages() {
        assertEquals(
            MessageContent.Audio("https://app.clomni.ai/f/voice-7d1c.m4a", "audio/mp4", 96_412, 14_260, ClientMessageFixtures.VOICE_WAVEFORM, null),
            content<MessageContent.Audio>("100-audio-voice-user.json"),
        )
        assertEquals(
            MessageContent.Audio("https://app.clomni.ai/f/cavab.mp3", "audio/mpeg", 381_220, null, null, null),
            content<MessageContent.Audio>("101-audio-operator-no-waveform.json"),
        )
        assertEquals("audio", fixture("104-reply-operator-to-voice.json").replyTo?.kind)
        assertEquals(emptyList<String>(), protocol.warnings)

        // A waveform that breaks the rule goes, the recording stays: plain bars.
        val broken = content<MessageContent.Audio>("103-invalid-audio-waveform-level.json")
        assertEquals(null to 8_000L, broken.waveform to broken.durationMs)
        assertLogged("audio.waveform")
        fun waveform(levels: String) = (contentOf("audio", """{"url":"https://a.b/v.m4a","mime":"audio/mp4","size":1,"waveform":$levels}""") as MessageContent.Audio).waveform
        assertEquals(listOf(0, 100, 7), waveform("[0, 100, 7.0]"))
        assertNull(waveform("[1.5]"))
        assertNull(waveform("[]"))
        assertNull(waveform("[\"5\"]"))
        assertNull(waveform(List(129) { "5" }.joinToString(",", "[", "]")))
        assertEquals(128, waveform(List(128) { "5" }.joinToString(",", "[", "]"))?.size)
        // Without its address or size it cannot play: the fallback text.
        assertUnknown("audio", """{"mime":"audio/mp4","size":1}""")
        assertUnknown("audio", """{"url":"https://a.b/v.m4a","mime":"audio/mp4"}""")
        assertNull((contentOf("audio", """{"url":"https://a.b/v.m4a","mime":"audio/mp4","size":1,"duration_ms":-1}""") as MessageContent.Audio).durationMs)
    }

    @Test
    fun contactForm() {
        val form = content<MessageContent.Form>("19-form-contact.json")
        assertEquals("frm_contact", form.formId)
        assertEquals("Göndər", form.submitTitle)
        assertNull(form.submitted)
        assertEquals(FormField("name", FormFieldType.TEXT, "Ad, soyad", true, 80, null, null, emptyList()), form.fields[0])
        assertEquals(FormField("phone", FormFieldType.PHONE, "Telefon", true, null, "AZ", null, emptyList()), form.fields[1])
        assertEquals(false, form.fields[2].required)
    }

    @Test
    fun everyFormFieldType() {
        val fields = content<MessageContent.Form>("20-form-all-field-types.json").fields
        assertEquals(
            listOf(
                FormFieldType.TEXT, FormFieldType.TEXTAREA, FormFieldType.PHONE, FormFieldType.EMAIL,
                FormFieldType.NUMBER, FormFieldType.SELECT, FormFieldType.DATE,
            ),
            fields.map { it.type },
        )
        assertEquals(
            listOf(
                FormField.Option("baku", "Bakı"),
                FormField.Option("ganja", "Gəncə"),
                FormField.Option("sumgait", "Sumqayıt"),
            ),
            fields.single { it.type == FormFieldType.SELECT }.options,
        )
    }

    @Test
    fun submittedFormIsTheSameMessageReadOnly() {
        val sent = fixture("21-form-submitted.json")
        val open = fixture("19-form-contact.json")
        assertEquals(open.id, sent.id)
        assertEquals(open.seq, sent.seq)
        assertEquals(false, sent.flow?.interactive)
        assertEquals(
            mapOf(
                "name" to JsonPrimitive("Aysel Məmmədova"),
                "phone" to JsonPrimitive("+994501234567"),
                "email" to JsonPrimitive("aysel@example.com"),
            ),
            (sent.content as MessageContent.Form).submitted,
        )
    }

    @Test
    fun systemMessages() {
        val queue = fixture("22-system-waiting-in-queue.json")
        assertEquals(Sender(SenderType.SYSTEM), queue.sender)
        assertEquals(MessageContent.System(SystemEvent.WaitingInQueue, "Sizi operatora yönləndiririk", 3), queue.content)
        assertEquals(
            MessageContent.System(SystemEvent.OperatorJoined, "Leyla söhbətə qoşuldu", null),
            content<MessageContent.System>("23-system-operator-joined.json"),
        )
        assertEquals(SystemEvent.ConversationClosed, content<MessageContent.System>("24-system-conversation-closed.json").event)
        // An event the SDK does not know is still a system message, shown by its text.
        assertEquals(
            MessageContent.System(SystemEvent.Unknown("survey_scheduled"), "Sizə qısa sorğu göndəriləcək", null),
            content<MessageContent.System>("25-system-unknown-event.json"),
        )
        assertEquals(
            listOf(SystemEvent.AssignedToTeam, SystemEvent.ConversationReopened),
            listOf("assigned_to_team", "conversation_reopened").map {
                (contentOf("system", """{"event":"$it","text":"T"}""") as MessageContent.System).event
            },
        )
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun cardsAndRating() {
        assertEquals(
            MessageContent.Card(
                listOf(
                    CardItem(
                        imageUrl = "https://app.clomni.ai/f/velo.jpg",
                        title = "Velosiped icarəsi",
                        subtitle = "30 dəq, 1 AZN",
                        buttons = listOf(
                            CardButton("btn_1", "Ətraflı", "node:V1", null),
                            CardButton("btn_2", "Sayt", null, "https://example.com"),
                        ),
                    ),
                ),
            ),
            content<MessageContent.Card>("26-card.json"),
        )
        val carousel = content<MessageContent.Card>("27-carousel.json").cards
        assertEquals(listOf("Tarif 1", "Tarif 2", "Tarif 3"), carousel.map { it.title })
        assertNull(carousel[0].imageUrl)
        assertEquals(
            MessageContent.Rating("Xidmətimizi qiymətləndirin", RatingScale.EMOJI_5, RatingComment.OPTIONAL, null),
            content<MessageContent.Rating>("28-rating.json"),
        )
    }

    @Test
    fun unknownTypeKeepsFallbackTextAndRawContent() {
        val message = fixture("29-unknown-type.json")
        assertEquals("poll", message.type)
        assertEquals(
            MessageContent.Unknown("poll", ProtocolFiles.json("fixtures/29-unknown-type.json").jsonObject.getValue("content")),
            message.content,
        )
        assertEquals("Hansı saat uyğundur? 10:00 / 14:00", message.fallbackText)
        assertEquals(28L, message.seq)
        assertLogged("msg_f29: unknown type \"poll\"")
    }

    @Test
    fun unknownFieldsAreSkipped() {
        assertEquals(MessageContent.Text("Yeni sahələr nəzərə alınmır"), content<MessageContent.Text>("30-unknown-fields.json"))
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun operatorWithoutAvatarAndOtherLanguage() {
        assertEquals(Sender(SenderType.OPERATOR, null, "Leyla", null), fixture("31-operator-no-avatar.json").sender)
        assertEquals("ru", fixture("32-other-language-ru.json").lang)
    }

    @Test
    fun invalidFixturesDegradeInsteadOfCrashing() {
        val emptyButtons = fixture("90-invalid-quick-replies-empty.json")
        assertEquals(MessageContent.Unknown::class, emptyButtons.content::class)
        assertEquals("Seçin", emptyButtons.fallbackText)
        assertLogged("msg_x90: quick_replies.buttons: expected at least one item")

        assertNull(protocol.json.parseMessage(ProtocolFiles.read("fixtures/91-invalid-missing-seq.json")))
        assertLogged("seq: expected an integer; message dropped")

        // Patterns are not checked: an unsupported language is kept as sent.
        assertEquals("de", fixture("95-invalid-lang.json").lang)

        assertEquals(
            MessageContent.Unknown::class,
            protocol.json.parseContent("form", ProtocolFiles.json("fixtures/94-invalid-select-without-options.json"))::class,
        )
        assertLogged("form.options: expected an array")

        // Two targets on a card button: both are kept, as on iOS.
        val both = protocol.json.parseContent("card", ProtocolFiles.json("fixtures/98-invalid-card-button-both.json"))
        assertEquals(
            CardButton("b", "Seç", "node:T", "https://example.com"),
            (both as MessageContent.Card).cards.single().buttons.single(),
        )
    }

    @Test
    fun notAMessage() {
        assertNull(protocol.json.parseMessage("{not json"))
        assertNull(protocol.json.parseMessage("[]"))
        assertNull(protocol.json.parseMessage(JsonArray(emptyList())))
        assertEquals(3, protocol.warnings.size)
    }

    @Test
    fun parsesAnElementOfALargerBody() {
        val page = Json.parseToJsonElement("[${ProtocolFiles.read("fixtures/01-text-bot.json")}]") as JsonArray
        assertEquals("msg_f01", protocol.json.parseMessage(page[0])?.id)
    }

    @Test
    fun messageWithAnUnusableEnvelopeIsDropped() {
        val required = listOf("id", "type", "content", "conversation_id", "sender", "created_at", "seq", "lang", "fallback_text")
        val broken = required.map { envelope(it to null) } + listOf(
            envelope("content" to JsonPrimitive("Salam")),
            envelope("sender" to Json.parseToJsonElement("""{"name":"Clomni"}""")),
            envelope("seq" to JsonPrimitive("1")),
            envelope("seq" to JsonPrimitive(1.5)),
            envelope("created_at" to JsonPrimitive("yesterday")),
            envelope("lang" to JsonNull),
        )
        for (json in broken) assertNull(json, protocol.json.parseMessage(json))
        assertEquals(broken.size, protocol.warnings.size)
        assertTrue(protocol.warnings.toString(), protocol.warnings.all { it.endsWith("; message dropped") })
    }

    @Test
    fun lenientEnvelopeValues() {
        val message = protocol.json.parseMessage(
            envelope(
                "id" to JsonPrimitive(""),
                "client_id" to JsonPrimitive(7),
                "flow" to JsonNull,
                "seq" to JsonPrimitive(3.0),
                "created_at" to JsonPrimitive("2026-10-01T14:30:00.250+04:00"),
                "sender" to Json.parseToJsonElement("""{"type":"ai_agent"}"""),
            ),
        )!!
        assertEquals("", message.id)
        assertNull(message.clientId)
        assertNull(message.flow)
        assertEquals(3L, message.seq)
        assertEquals(Instant.parse("2026-10-01T10:30:00.250Z").toEpochMilli(), message.createdAt)
        assertEquals(Sender(SenderType.UNKNOWN), message.sender)
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun brokenFlowIsDroppedNotTheMessage() {
        for (flow in listOf("""{"flow_id":"flw_a","node_id":"A"}""", """{"flow_id":"flw_a","interactive":true}""", "\"flw_a\"")) {
            val message = protocol.json.parseMessage(envelope("flow" to Json.parseToJsonElement(flow)))!!
            assertNull(flow, message.flow)
            assertEquals(MessageContent.Text::class, message.content::class)
        }
        assertEquals(3, protocol.warnings.size)
        assertLogged("msg_f01: interactive: expected a boolean; shown without its flow")
    }

    @Test
    fun brokenContentOfAKnownType() {
        assertUnknown("text", """{"text":5}""")
        assertUnknown("quick_replies", """{"buttons":"none"}""")
        assertUnknown("quick_replies", """{"buttons":["btn"]}""")
        assertUnknown("quick_replies", """{"buttons":[{"id":"a","title":"A"}]}""")
        assertUnknown("image", """{"thumb_url":"https://x/a.png"}""")
        assertUnknown("file", """{"url":"u","name":"n","mime":"m"}""")
        assertUnknown("form", """{"form_id":"frm_a","submit_title":"OK","fields":[]}""")
        assertUnknown("form", """{"form_id":"frm_a","submit_title":"OK","fields":[{"key":"a","label":"A"}]}""")
        assertUnknown("form", """{"form_id":"frm_a","submit_title":"OK","fields":[{"key":"c","type":"select","label":"C","options":[{"value":"x"}]}]}""")
        assertUnknown("system", """{"event":"operator_joined"}""")
        assertUnknown("card", """{"cards":[]}""")
        assertUnknown("card", """{"cards":[{"title":"T","buttons":[{"id":"b","title":"B"}]}]}""")
        assertUnknown("card", """{"cards":[{"title":"T","buttons":{}}]}""")
        assertUnknown("rating", """{"text":"R","scale":"nps_10"}""")
        assertUnknown("text", "\"Salam\"")
        assertLogged("rating.scale: unknown scale \"nps_10\"")
        assertLogged("text: expected an object; shown as fallback_text")
    }

    @Test
    fun lenientContentValues() {
        val buttons = contentOf("quick_replies", """{"buttons":[{"id":"a","title":"","payload":"p"}],"layout":"grid"}""")
        assertEquals(MessageContent.QuickReplies(null, listOf(Button("a", "", null, "p")), QuickRepliesLayout.VERTICAL, false, false), buttons)

        val image = contentOf("image", """{"url":"https://x/a.png","width":0,"height":3000000000}""") as MessageContent.Image
        assertNull(image.width)
        assertNull(image.height)
        assertEquals(-1L, (contentOf("file", """{"url":"u","name":"n","size":-1,"mime":"m"}""") as MessageContent.File).size)

        val form = contentOf(
            "form",
            """{"form_id":"frm_a","submit_title":"OK",
               "fields":[{"key":"s","type":"signature","label":"S","max_length":0,"placeholder":"…","options":[1]}],
               "submitted":{"n":3,"x":null}}""",
        ) as MessageContent.Form
        // A field type added later is shown as a text field; options only belong to a select.
        assertEquals(FormField("s", FormFieldType.TEXT, "S", false, 0, null, "…", emptyList()), form.fields.single())
        assertEquals(mapOf("n" to JsonPrimitive(3), "x" to JsonNull), form.submitted)

        assertEquals(
            MessageContent.Card(listOf(CardItem(null, "T", null, emptyList()))),
            contentOf("card", """{"cards":[{"title":"T","buttons":null}]}"""),
        )
        assertEquals(0, (contentOf("system", """{"event":"waiting_in_queue","text":"T","position":0}""") as MessageContent.System).position)
    }

    @Test
    fun ratingComment() {
        fun comment(json: String) = (contentOf("rating", """{"text":"R","scale":"star_5"$json}""") as MessageContent.Rating).comment
        assertEquals(RatingComment.HIDDEN, comment(""))
        assertEquals(RatingComment.HIDDEN, comment(""","comment":"none""""))
        assertEquals(RatingComment.REQUIRED, comment(""","comment":"required""""))
        assertEquals(RatingComment.OPTIONAL, comment(""","comment":"later""""))
        assertEquals(
            mapOf("score" to JsonPrimitive(4)),
            (contentOf("rating", """{"text":"R","scale":"star_5","submitted":{"score":4}}""") as MessageContent.Rating).submitted,
        )
    }
}
