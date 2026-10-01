package ai.clomni.messenger.protocol

import ai.clomni.messenger.protocol.RealtimeEvent.Payload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class RealtimeEventTest {

    private val protocol = RecordingProtocol()

    private fun fixture(name: String): RealtimeEvent = protocol.json.parseEvent(ProtocolFiles.read("fixtures/$name"))!!

    private fun data(event: String, data: String): Payload? =
        protocol.json.parseEvent("""{"event":"$event","data":$data,"ts":"2026-10-01T10:30:01Z"}""")?.data

    @Test
    fun frame() {
        assertEquals(
            RealtimeEvent("ready", Payload.Ready("usr_12345", 25), Instant.parse("2026-10-01T10:30:01Z").toEpochMilli()),
            fixture("33-event-ready.json"),
        )
        assertNull(protocol.json.parseEvent("""{"event":"unread.changed","data":{"total":1},"ts":"soon"}""")?.ts)
    }

    @Test
    fun knownEvents() {
        assertEquals(
            Payload.Typing("conv_5521", Sender(SenderType.BOT, "bot_default", "Clomni", "https://app.clomni.ai/a/bot.png"), true),
            fixture("36-event-typing.json").data,
        )
        assertEquals(Payload.Read("conv_5521", 12, SenderType.OPERATOR), fixture("37-event-read.json").data)
        assertEquals(
            Payload.ConversationUpdated(
                RealtimeEvent.ConversationUpdate(
                    id = "conv_5521",
                    status = ConversationStatus.OPEN,
                    assignee = Assignee("Leyla", "https://app.clomni.ai/a/leyla.png", online = true),
                    unreadCount = 1,
                ),
            ),
            fixture("38-event-conversation-updated.json").data,
        )
        assertEquals(Payload.UnreadChanged(2), fixture("39-event-unread-changed.json").data)
        assertEquals(Payload.ConfigChanged("W/\"7f3a\""), fixture("40-event-config-changed.json").data)
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun messageEventsCarryTheParsedMessage() {
        val created = fixture("34-event-message-created.json").data as Payload.MessageCreated
        assertEquals("msg_f23", created.message.id)
        assertEquals(
            MessageContent.System(MessageContent.SystemEvent.OperatorJoined, "Leyla söhbətə qoşuldu", null),
            created.message.content,
        )
        val updated = fixture("35-event-message-updated.json").data as Payload.MessageUpdated
        assertEquals(protocol.json.parseMessage(ProtocolFiles.read("fixtures/21-form-submitted.json")), updated.message)
    }

    @Test
    fun unknownAndBrokenEventsAreIgnored() {
        assertEquals(
            RealtimeEvent("conversation.rated", Payload.Unknown("conversation.rated"), Instant.parse("2026-10-01T10:30:01Z").toEpochMilli()),
            fixture("41-event-unknown.json"),
        )
        assertEquals(Payload.Unknown("ready"), fixture("97-invalid-event-ready-without-data.json").data)
        assertTrue(protocol.warnings.toString(), "unknown event \"conversation.rated\" ignored" in protocol.warnings)
        assertTrue(protocol.warnings.toString(), "ready: data: expected an object; event ignored" in protocol.warnings)

        val broken = listOf(
            "ready" to """{"user_id":"usr_1"}""",
            "message.created" to """{"id":"msg_1","conversation_id":"conv_1"}""",
            "typing" to """{"conversation_id":"conv_1","sender":{"type":"bot"},"state":"paused"}""",
            "typing" to """{"conversation_id":"conv_1","state":"on"}""",
            "read" to """{"conversation_id":"conv_1","by":"operator"}""",
            "conversation.updated" to """{"id":"conv_1","status":"open","assignee":{"online":true}}""",
            "unread.changed" to """{"total":"2"}""",
            "config.changed" to """{"etag":7}""",
        )
        for ((event, data) in broken) assertEquals(data, Payload.Unknown(event), data(event, data))
    }

    @Test
    fun lenientValues() {
        assertEquals(
            Payload.Typing("conv_1", Sender(SenderType.OPERATOR, name = "Leyla"), false),
            data("typing", """{"conversation_id":"conv_1","sender":{"type":"operator","name":"Leyla"},"state":"off"}"""),
        )
        assertEquals(
            Payload.ConversationUpdated(RealtimeEvent.ConversationUpdate("conv_1", ConversationStatus.UNKNOWN, null, null)),
            data("conversation.updated", """{"id":"conv_1","status":"snoozed","assignee":null}"""),
        )
        assertEquals(
            Payload.ConversationUpdated(
                RealtimeEvent.ConversationUpdate("conv_1", ConversationStatus.QUEUED, Assignee("Rauf", null, null), 0),
            ),
            data("conversation.updated", """{"id":"conv_1","status":"queued","assignee":{"name":"Rauf"},"unread_count":0}"""),
        )
        // Limits are not checked: the values are kept as sent.
        assertEquals(Payload.Ready("usr_1", 0), data("ready", """{"user_id":"usr_1","heartbeat_sec":0}"""))
        assertEquals(Payload.UnreadChanged(-1), data("unread.changed", """{"total":-1}"""))
        assertEquals(Payload.Read("conv_1", 3, SenderType.UNKNOWN), data("read", """{"conversation_id":"conv_1","up_to_seq":3,"by":"bot_x"}"""))
        assertEquals(RealtimeEvent("ping", Payload.Unknown("ping"), null), protocol.json.parseEvent("""{"event":"ping"}"""))
    }

    @Test
    fun notAFrame() {
        assertNull(protocol.json.parseEvent("ping"))
        assertNull(protocol.json.parseEvent("""{"data":{}}"""))
        assertNull(protocol.json.parseEvent("""{"event":5}"""))
        assertEquals(3, protocol.warnings.size)
    }
}
