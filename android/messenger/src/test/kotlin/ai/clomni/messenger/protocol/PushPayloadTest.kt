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
                title = "Leyla · Apar",
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
    fun fcmDataValuesAreStrings() {
        val push = protocol.json.parsePush(
            """{"clomni":"1","type":"message","conversation_id":"conv_1","title":"T","body":"B","unread_total":"3"}""",
        )
        assertEquals(3, push?.unreadTotal)
    }

    @Test
    fun notAClomniPush() {
        assertNull(protocol.json.parsePush("""{"type":"message","conversation_id":"conv_1","title":"T","body":"B"}"""))
        assertNull(protocol.json.parsePush("""{"clomni":1,"type":"message","conversation_id":"conv_1","title":"T","body":"B"}"""))
        // Another SDK's push is normal traffic, not worth a log line.
        assertEquals(emptyList<String>(), protocol.warnings)

        assertNull(protocol.json.parsePush("""{"clomni":"1","type":"message","title":"T","body":"B"}"""))
        assertNull(protocol.json.parsePush("not json"))
        assertEquals(2, protocol.warnings.size)
    }
}
