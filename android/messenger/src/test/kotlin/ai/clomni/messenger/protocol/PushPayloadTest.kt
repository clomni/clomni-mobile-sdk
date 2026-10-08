package ai.clomni.messenger.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PushPayloadTest {

    private val protocol = RecordingProtocol()

    @Test
    fun operatorReply() {
        assertEquals(
            PushPayload(
                type = "message",
                conversationId = "conv_5521",
                messageId = "msg_f02",
                title = "Leyla · Example",
                body = "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
                avatarUrl = "https://app.clomni.ai/a/leyla.png",
                unreadTotal = 1,
            ),
            protocol.json.parsePush(ProtocolFiles.read("fixtures/44-push-message.json")),
        )
    }

    @Test
    fun overlongBodyIsKept() {
        val push = protocol.json.parsePush(ProtocolFiles.read("fixtures/92-invalid-push-body-too-long.json"))!!
        assertEquals(181, push.body.length)
        assertNull(push.messageId)
        assertNull(push.unreadTotal)
    }

    @Test
    fun fcmDataMessage() {
        val data = mapOf(
            "clomni" to "1",
            "type" to "message",
            "conversation_id" to "conv_1",
            "message_id" to "msg_1",
            "title" to "Leyla · Example",
            "body" to "Salam",
            "unread_total" to "3",
        )
        assertEquals(PushPayload("message", "conv_1", "msg_1", "Leyla · Example", "Salam", null, 3), protocol.json.parsePush(data))
        assertNull(protocol.json.parsePush(data - "clomni"))
    }

    @Test
    fun notAClomniPush() {
        assertNull(protocol.json.parsePush("""{"type":"message","conversation_id":"conv_1","title":"T","body":"B"}"""))
        assertNull(protocol.json.parsePush("""{"clomni":1,"type":"message","conversation_id":"conv_1","title":"T","body":"B"}"""))
        assertNull(protocol.json.parsePush("""{"clomni":"1","type":"message","title":"T","body":"B"}"""))
        assertNull(protocol.json.parsePush("not json"))
        assertEquals(
            listOf("not a Clomni push; push dropped", "not a Clomni push; push dropped", "conversation_id: expected a string; push dropped"),
            protocol.warnings.take(3),
        )
        assertEquals(4, protocol.warnings.size)
    }
}
