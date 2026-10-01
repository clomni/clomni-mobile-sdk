package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClientMessageTest {

    private val protocol = RecordingProtocol()

    private fun encoded(message: ClientMessage) = Json.parseToJsonElement(protocol.json.encode(message)).jsonObject

    @Test
    fun newMessagesGetAFreshUuidV4() {
        val first = ClientMessage.Text("Salam")
        val second = ClientMessage.Text("Salam")
        val uuidV4 = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
        assertTrue(first.clientId, uuidV4.matches(first.clientId))
        assertNotEquals(first.clientId, second.clientId)
    }

    @Test
    fun backButton() {
        assertEquals(
            ClientMessage.ButtonReply("msg_f10", "back", "nav:back", "c1"),
            ClientMessage.back("msg_f10", clientId = "c1"),
        )
    }

    @Test
    fun wireTypes() {
        assertEquals(
            listOf("text", "button_reply", "form_submit", "attachment", "rating_submit"),
            listOf(
                ClientMessage.Text("a"),
                ClientMessage.ButtonReply("msg_1", "b", "p"),
                ClientMessage.FormSubmit("msg_1", "frm_1", emptyMap()),
                ClientMessage.Attachment("upl_1"),
                ClientMessage.RatingSubmit("msg_1", 5),
            ).map { it.type },
        )
    }

    @Test
    fun missingOptionalsGoOutAsNull() {
        assertEquals(
            Json.parseToJsonElement("""{"client_id":"c1","type":"attachment","content":{"upload_id":"upl_1","caption":null}}"""),
            encoded(ClientMessage.Attachment("upl_1", clientId = "c1")),
        )
        assertEquals(
            Json.parseToJsonElement("""{"client_id":"c2","type":"rating_submit","content":{"reply_to":"msg_1","score":3,"comment":null}}"""),
            encoded(ClientMessage.RatingSubmit("msg_1", 3, clientId = "c2")),
        )
    }

    @Test
    fun textIsEscaped() {
        val text = "Dırnaq \" və \\ işarəsi\nyeni sətir 👍"
        assertEquals(text, encoded(ClientMessage.Text(text, "c1"))["content"]!!.jsonObject["text"]!!.jsonPrimitive.content)
    }

    @Test
    fun everyMessageReadsBackFromItsEncoding() {
        val messages = listOf(
            ClientMessage.Text("Salam"),
            ClientMessage.back("msg_1"),
            ClientMessage.FormSubmit(
                replyTo = "msg_1",
                formId = "frm_1",
                values = mapOf("count" to JsonPrimitive(3), "city" to JsonPrimitive("baku"), "note" to JsonNull),
            ),
            ClientMessage.Attachment("upl_1"),
            ClientMessage.Attachment("upl_1", "Şəkil"),
            ClientMessage.RatingSubmit("msg_1", 4),
            ClientMessage.RatingSubmit("msg_1", 5, "Əla"),
        )
        for (message in messages) assertEquals(message, protocol.json.parseClientMessage(protocol.json.encode(message)))
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun brokenStoredMessages() {
        val broken = listOf(
            "[]",
            """{"client_id":"c1","type":"sticker","content":{}}""",
            """{"client_id":"c1","type":"text"}""",
            """{"type":"text","content":{"text":"a"}}""",
            """{"client_id":"c1","type":"rating_submit","content":{"reply_to":"msg_1","score":"5"}}""",
            """{"client_id":"c1","type":"form_submit","content":{"reply_to":"msg_1","form_id":"frm_1"}}""",
        )
        for (json in broken) assertNull(json, protocol.json.parseClientMessage(json))
        assertEquals(broken.size, protocol.warnings.size)
        assertTrue(protocol.warnings.toString(), "type: unknown client message type \"sticker\"; client message dropped" in protocol.warnings)
    }

    @Test
    fun formValuesKeepTheirJsonTypes() {
        val values = buildJsonObject {
            put("count", JsonPrimitive(3))
            put("agree", JsonPrimitive(true))
        }
        val content = encoded(ClientMessage.FormSubmit("msg_1", "frm_1", values, "c1"))["content"]!!.jsonObject
        assertEquals(values, content["values"])
    }
}
