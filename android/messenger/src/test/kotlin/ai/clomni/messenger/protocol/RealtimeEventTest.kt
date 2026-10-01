package ai.clomni.messenger.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RealtimeEventTest {

    private val protocol = RecordingProtocol()

    private fun fixture(name: String): RealtimeEvent? = protocol.json.parseEvent(ProtocolFiles.read("fixtures/$name"))

    private fun frame(event: String, data: String) = protocol.json.parseEvent("""{"event":"$event","data":$data,"ts":"2026-10-01T10:30:01Z"}""")

    @Test
    fun knownEvents() {
        assertEquals(RealtimeEvent.Ready("usr_12345", 25), fixture("33-event-ready.json"))
        assertEquals(
            RealtimeEvent.Typing("conv_5521", Sender(SenderType.BOT, "bot_default", "Clomni", "https://app.clomni.ai/a/bot.png"), true),
            fixture("36-event-typing.json"),
        )
        assertEquals(RealtimeEvent.Read("conv_5521", 12, SenderType.OPERATOR), fixture("37-event-read.json"))
        assertEquals(
            RealtimeEvent.ConversationUpdated(
                id = "conv_5521",
                status = ConversationStatus.OPEN,
                assignee = Assignee("Leyla", "https://app.clomni.ai/a/leyla.png", online = true),
                unreadCount = 1,
            ),
            fixture("38-event-conversation-updated.json"),
        )
        assertEquals(RealtimeEvent.UnreadChanged(2), fixture("39-event-unread-changed.json"))
        assertEquals(RealtimeEvent.ConfigChanged("W/\"7f3a\""), fixture("40-event-config-changed.json"))
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun messageEventsCarryTheParsedMessage() {
        val created = fixture("34-event-message-created.json") as RealtimeEvent.MessageCreated
        assertEquals("msg_f23", created.message.id)
        assertEquals(MessageContent.System("operator_joined", "Leyla söhbətə qoşuldu", null), created.message.content)

        val updated = fixture("35-event-message-updated.json") as RealtimeEvent.MessageUpdated
        assertEquals(protocol.json.parseMessage(ProtocolFiles.read("fixtures/21-form-submitted.json")), updated.message)
    }

    @Test
    fun unknownAndBrokenEventsAreIgnored() {
        assertEquals(RealtimeEvent.Unknown("conversation.rated"), fixture("41-event-unknown.json"))
        assertEquals(RealtimeEvent.Unknown("ready"), fixture("97-invalid-event-ready-without-data.json"))
        assertTrue(protocol.warnings.toString(), protocol.warnings.any { "'conversation.rated'" in it })
        assertTrue(protocol.warnings.toString(), protocol.warnings.any { "'ready'" in it && "data" in it })

        val broken = listOf(
            "ready" to """{"user_id":"usr_1","heartbeat_sec":0}""",
            "message.created" to """{"id":"msg_1","conversation_id":"conv_1"}""",
            "typing" to """{"conversation_id":"conv_1","sender":{"type":"bot"},"state":"paused"}""",
            "typing" to """{"conversation_id":"conv_1","state":"on"}""",
            "read" to """{"conversation_id":"conv_1","by":"operator"}""",
            "conversation.updated" to """{"id":"conv_1","status":"open","assignee":{"online":true}}""",
            "unread.changed" to """{"total":-1}""",
            "config.changed" to """{"etag":""}""",
        )
        for ((event, data) in broken) assertEquals(data, RealtimeEvent.Unknown(event), frame(event, data))
    }

    @Test
    fun lenientValues() {
        assertEquals(
            RealtimeEvent.Typing("conv_1", Sender(SenderType.OPERATOR, name = "Leyla"), false),
            frame("typing", """{"conversation_id":"conv_1","sender":{"type":"operator","name":"Leyla"},"state":"off"}"""),
        )
        assertEquals(
            RealtimeEvent.ConversationUpdated("conv_1", ConversationStatus.UNKNOWN, null, null),
            frame("conversation.updated", """{"id":"conv_1","status":"snoozed","assignee":null}"""),
        )
        assertEquals(
            RealtimeEvent.ConversationUpdated("conv_1", ConversationStatus.QUEUED, Assignee("Rauf", null, false), 0),
            frame("conversation.updated", """{"id":"conv_1","status":"queued","assignee":{"name":"Rauf"},"unread_count":0}"""),
        )
    }

    @Test
    fun notAFrame() {
        assertNull(protocol.json.parseEvent("ping"))
        assertNull(protocol.json.parseEvent("""{"data":{}}"""))
        assertNull(protocol.json.parseEvent("""{"event":""}"""))
        assertEquals(3, protocol.warnings.size)
    }
}
