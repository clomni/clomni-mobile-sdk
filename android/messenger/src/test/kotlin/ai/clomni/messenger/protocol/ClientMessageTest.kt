package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClientMessageTest {

    private val protocol = ProtocolJson()

    private fun encoded(message: ClientMessage) = Json.parseToJsonElement(protocol.encode(message)).jsonObject

    @Test
    fun newMessagesGetAFreshUuidV4() {
        val first = ClientMessage.Text("Salam")
        val second = ClientMessage.Text("Salam")
        val uuidV4 = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
        assertTrue(first.clientId, uuidV4.matches(first.clientId))
        assertNotEquals(first.clientId, second.clientId)
        assertTrue(first.isValid)
    }

    @Test
    fun nullOptionalsAreLeftOut() {
        assertEquals(
            Json.parseToJsonElement("""{"client_id":"c1","type":"attachment","content":{"upload_id":"upl_1"}}"""),
            encoded(ClientMessage.Attachment("upl_1", clientId = "c1")),
        )
        assertEquals(
            Json.parseToJsonElement("""{"client_id":"c2","type":"rating_submit","content":{"reply_to":"msg_1","score":3}}"""),
            encoded(ClientMessage.RatingSubmit("msg_1", 3, clientId = "c2")),
        )
    }

    @Test
    fun textIsEscaped() {
        val text = "Dırnaq \" və \\ işarəsi\nyeni sətir 👍"
        assertEquals(text, encoded(ClientMessage.Text(text, "c1"))["content"]!!.jsonObject["text"]!!.jsonPrimitive.content)
    }

    @Test
    fun validityFollowsTheSchema() {
        val emoji = "👍".repeat(ClientMessage.MAX_TEXT_LENGTH)
        assertTrue("4000 emoji are 4000 characters", ClientMessage.Text(emoji).isValid)
        assertTrue(ClientMessage.Text("a".repeat(4000)).isValid)
        assertTrue(ClientMessage.Attachment("upl_1").isValid)
        assertTrue(ClientMessage.FormSubmit("msg_1", "frm_1", emptyMap()).isValid)

        val invalid = listOf(
            ClientMessage.Text(""),
            ClientMessage.Text("a".repeat(4001)),
            ClientMessage.Text("a", clientId = ""),
            ClientMessage.Text("a", clientId = "c".repeat(65)),
            ClientMessage.ButtonReply("msg_1", "btn_1", ""),
            ClientMessage.ButtonReply("", "btn_1", "node:A"),
            ClientMessage.FormSubmit("msg_1", "", emptyMap()),
            ClientMessage.Attachment(""),
            ClientMessage.Attachment("upl_1", "a".repeat(4001)),
            ClientMessage.RatingSubmit("msg_1", 0),
            ClientMessage.RatingSubmit("msg_1", 6),
            ClientMessage.RatingSubmit("msg_1", 5, "a".repeat(4001)),
        )
        for (message in invalid) assertFalse(message.toString().take(80), message.isValid)
    }
}
