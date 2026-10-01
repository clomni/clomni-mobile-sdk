package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class MobileApiModelsTest {

    private val protocol = RecordingProtocol()

    private fun millis(time: String) = Instant.parse(time).toEpochMilli()

    private val conversationJson = """{"id":"conv_5521","status":"bot","assignee":null,"unread_count":1,"last_message":null,
        "flow":{"flow_id":"flw_apar_az","node_id":"S"},"opened_from":"profile_support","created_at":"2026-10-01T10:30:00Z"}"""

    @Test
    fun session() {
        val json = """{"session_token":"st_9d2f4c1e7a0b","expires_at":"2026-10-02T10:30:00Z","refresh_token":"rt_4c1e7a0b9d2f",
            "user":{"id":"usr_12345","anonymous":false,"language":"az"},"ws_url":"wss://app.clomni.ai/v1/realtime"}"""
        val session = MobileSession(
            sessionToken = "st_9d2f4c1e7a0b",
            expiresAt = millis("2026-10-02T10:30:00Z"),
            refreshToken = "rt_4c1e7a0b9d2f",
            userId = "usr_12345",
            anonymous = false,
            language = "az",
            wsUrl = "wss://app.clomni.ai/v1/realtime",
        )
        assertEquals(session, protocol.json.parseSession(json))
        assertEquals(session, protocol.json.parseSession(session.toJson().toString()))
        assertNull(protocol.json.parseSession("""{"session_token":"st_1"}"""))
    }

    @Test
    fun conversation() {
        val conversation = Conversation(
            id = "conv_5521",
            status = ConversationStatus.BOT,
            assignee = null,
            unreadCount = 1,
            lastMessage = null,
            flow = Conversation.FlowStep("flw_apar_az", "S"),
            openedFrom = "profile_support",
            createdAt = millis("2026-10-01T10:30:00Z"),
        )
        assertEquals(conversation, protocol.json.parseConversation(conversationJson))
        val full = conversation.copy(
            assignee = Assignee("Leyla", "https://app.clomni.ai/a/leyla.png", true),
            lastMessage = protocol.json.parseMessage(ProtocolFiles.read("fixtures/02-text-operator-markdown.json")),
            flow = null,
        )
        assertEquals(full, protocol.json.parseConversation(full.toJson().toString()))
        assertEquals(
            Conversation("conv_1", ConversationStatus.UNKNOWN, null, 0, null, null, null, millis("2026-10-01T10:30:00Z")),
            protocol.json.parseConversation(
                """{"id":"conv_1","status":"snoozed","flow":{"flow_id":"flw_a"},"created_at":"2026-10-01T10:30:00Z"}""",
            ),
        )
    }

    @Test
    fun pagesDropAnItemTheyCannotRead() {
        val page = protocol.json.parseConversationPage(
            """{"conversations":[$conversationJson,{"id":"conv_2"}],"next_cursor":"c2"}""",
        )!!
        assertEquals(listOf("conv_5521"), page.conversations.map { it.id })
        assertEquals("c2", page.nextCursor)
        assertTrue(protocol.warnings.toString(), protocol.warnings.single().endsWith("item dropped"))

        val messages = protocol.json.parseMessagePage(
            """{"messages":[${ProtocolFiles.read("fixtures/01-text-bot.json")},${ProtocolFiles.read("fixtures/91-invalid-missing-seq.json")}],
               "has_more":true}""",
        )!!
        assertEquals(listOf("msg_f01"), messages.messages.map { it.id })
        assertTrue(messages.hasMore)
        assertNull(protocol.json.parseMessagePage("""{"has_more":false}"""))
    }

    @Test
    fun conversationWithMessagesAndFlowTrigger() {
        val body = """{"conversation":$conversationJson,"messages":[${ProtocolFiles.read("fixtures/09-apar-level1-A.json")}]}"""
        val created = protocol.json.parseConversationWithMessages(body)!!
        assertEquals("conv_5521", created.conversation.id)
        assertEquals(listOf("msg_f09"), created.messages.map { it.id })
        assertEquals(FlowTriggerResult(true, created), protocol.json.parseFlowTrigger("""{"started":true,"conversation":$body}"""))
        assertEquals(FlowTriggerResult(false, null), protocol.json.parseFlowTrigger("""{"started":false,"conversation":null}"""))
        assertNull(protocol.json.parseFlowTrigger("""{"conversation":null}"""))
    }

    @Test
    fun userAndUpload() {
        assertEquals(
            MobileUser("usr_12345", false, "Aysel Məmmədova", "aysel@example.com", null, "az", mapOf("plan" to JsonPrimitive("premium"))),
            protocol.json.parseUser(
                """{"id":"usr_12345","anonymous":false,"name":"Aysel Məmmədova","email":"aysel@example.com","phone":null,
                   "language":"az","custom_attributes":{"plan":"premium"}}""",
            ),
        )
        assertEquals(MobileUser("usr_1", true, null, null, null, null, emptyMap()), protocol.json.parseUser("""{"id":"usr_1","anonymous":true}"""))
        assertNull(protocol.json.parseUser("""{"id":"usr_1"}"""))
        assertEquals(
            UploadedFile("upl_77ab", "https://app.clomni.ai/f/velo.jpg", "velo.jpg", 482_113, "image/jpeg"),
            protocol.json.parseUpload(
                """{"upload_id":"upl_77ab","url":"https://app.clomni.ai/f/velo.jpg","name":"velo.jpg","size":482113,"mime":"image/jpeg"}""",
            ),
        )
        assertNull(protocol.json.parseUpload("""{"upload_id":"upl_77ab"}"""))
    }

    @Test
    fun serverError() {
        assertEquals(
            ServerError("validation_failed", "phone is not a valid phone number", "req_5f2a", mapOf("phone" to "invalid")),
            protocol.json.parseServerError(
                """{"error":{"code":"validation_failed","message":"phone is not a valid phone number","request_id":"req_5f2a",
                   "fields":{"phone":"invalid","n":1}}}""",
            ),
        )
        assertEquals(ServerError("internal", "", null, emptyMap()), protocol.json.parseServerError("""{"error":{"code":"internal"}}"""))
        assertNull(protocol.json.parseServerError("<html>Bad gateway</html>"))
        assertNull(protocol.json.parseServerError("""{"message":"oops"}"""))
        assertEquals(emptyList<String>(), protocol.warnings)
    }

    @Test
    fun everyMessageFixtureSurvivesTheWireEncoding() {
        val messages = ProtocolFiles.entries()
            .filter { it.schema == "message.json" }
            .mapNotNull { protocol.json.parseMessage(ProtocolFiles.read(it.path)) }
        assertTrue(messages.size > 30)
        for (message in messages) assertEquals(message.id, message, protocol.json.parseMessage(message.toJson().toString()))
    }

    @Test
    fun formatsTimesAsTheServerDoes() {
        for (time in listOf("2026-10-01T10:30:00.000Z", "1970-01-01T00:00:00.000Z", "2024-02-29T23:59:59.999Z", "1969-12-31T23:59:59.500Z")) {
            assertEquals(time, Iso8601.format(millis(time)))
        }
    }
}
