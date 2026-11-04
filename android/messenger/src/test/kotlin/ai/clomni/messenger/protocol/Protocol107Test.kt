package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** SDK 1.0.7 (contract §1, §3): a deleted message, the config's tab bar, news_on_home and FAQ, GET /faq. */
class Protocol107Test {
    private val protocol = RecordingProtocol()

    private fun message(type: String, content: String, extra: String = "") = protocol.json.parseMessage(
        """{"id":"msg_9","conversation_id":"conv_1","type":"$type","sender":{"type":"user","id":"usr_1"},
           "created_at":"2026-11-04T10:00:00Z","seq":7,"lang":"az","content":$content,"fallback_text":"Bu mesaj silindi"$extra}""",
    )!!

    private fun config(json: String): MessengerConfig = protocol.json.parseConfig(json)!!

    @Test
    fun aDeletedMessageWhateverItsType() {
        // The type the contract names, and a message that keeps its own type with the deleted content.
        for (type in listOf("deleted", "text", "image", "audio")) {
            val deleted = message(type, """{"type":"deleted"}""", ""","reply_to":null""")
            assertEquals(type, MessageContent.Deleted, deleted.content)
            assertNull(deleted.replyTo)
            assertEquals(7L, deleted.seq)
        }
        assertEquals("nothing logged for a valid deleted message", emptyList<String>(), protocol.warnings)
        // A content of another type is not mistaken for one.
        assertEquals(MessageContent.Text("deleted"), message("text", """{"text":"deleted"}""").content)
    }

    @Test
    fun aDeletedMessageIsKeptAsDeleted() {
        val deleted = message("text", """{"type":"deleted"}""")
        val again = protocol.json.parseMessage(deleted.toJson().toString())
        assertEquals(deleted, again)
        assertEquals("""{"type":"deleted"}""", deleted.toJson()["content"].toString())
    }

    @Test
    fun tabBarNewsOnHomeAndFaq() {
        val off = config("{}")
        assertFalse("no tab_bar: as before", off.home.tabBar)
        assertEquals(2, off.home.newsOnHome)
        assertFalse("no faq: off", off.faqEnabled)

        val on = config("""{"home":{"tab_bar":true,"news_on_home":3,"cards":["send","news","faq"]},"faq":{"enabled":true}}""")
        assertTrue(on.home.tabBar)
        assertEquals(3, on.home.newsOnHome)
        assertTrue(on.faqEnabled)
        assertEquals(
            listOf(MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.SEND, MessengerConfig.HomeCard.NEWS, MessengerConfig.HomeCard.FAQ),
            on.home.cards,
        )
        // 1–3; anything else is brought into it, a wrong type is the default.
        assertEquals(1, config("""{"home":{"news_on_home":0}}""").home.newsOnHome)
        assertEquals(3, config("""{"home":{"news_on_home":9}}""").home.newsOnHome)
        assertEquals(2, config("""{"home":{"news_on_home":"3","tab_bar":"yes"}}""").home.newsOnHome)
        assertFalse(config("""{"home":{"tab_bar":"yes"}}""").home.tabBar)
        assertFalse(config("""{"faq":{"enabled":"true"}}""").faqEnabled)
        assertFalse(config("""{"faq":true}""").faqEnabled)
    }

    @Test
    fun theQuestions() {
        val faq = protocol.json.parseFaq(
            """{"items":[
                 {"id":"faq_12","question":"Balansı necə artırım?","answer":"**Kartla** və ya terminalla.","updated_at":"2026-11-01T09:00:00Z"},
                 {"id":"faq_13","question":"Kart necə silinir?"},
                 {"id":"faq_14","question":"  "},
                 {"question":"Id yoxdur"},
                 "broken"
               ]}""",
        )!!
        assertEquals(
            listOf(
                FaqItem("faq_12", "Balansı necə artırım?", "**Kartla** və ya terminalla.", Instant.parse("2026-11-01T09:00:00Z").toEpochMilli()),
                FaqItem("faq_13", "Kart necə silinir?", "", null),
            ),
            faq,
        )
        assertTrue(protocol.warnings.toString(), protocol.warnings.any { "faq_14 without a question" in it })
        assertTrue(protocol.warnings.any { "faq item without an id" in it })
        assertEquals(emptyList<FaqItem>(), protocol.json.parseFaq("""{"items":[]}"""))
        assertEquals(emptyList<FaqItem>(), protocol.json.parseFaq("{}"))
        assertNull("not JSON", protocol.json.parseFaq("<html>"))
    }

    @Test
    fun aDeletedContentOnItsOwn() {
        assertEquals(MessageContent.Deleted, protocol.json.parseContent("deleted", Json.parseToJsonElement("{}")))
        assertEquals(MessageContent.Deleted, protocol.json.parseContent("rating", Json.parseToJsonElement("""{"type":"deleted"}""")))
    }
}
