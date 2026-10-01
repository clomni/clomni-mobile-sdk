package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonElement

// Response bodies of the Mobile API (protocol/openapi.yaml), with the same names as the iOS SDK. A list drops an item
// it cannot read (with a log line) rather than failing the whole page.

/** POST /mobile/sessions and /mobile/sessions/refresh. */
internal data class MobileSession(
    val sessionToken: String,
    /** Epoch milliseconds, UTC. */
    val expiresAt: Long,
    /** Single-use: a refresh answers with the next one. */
    val refreshToken: String,
    val userId: String,
    val anonymous: Boolean,
    val language: String?,
    val wsUrl: String,
)

internal data class Conversation(
    val id: String,
    val status: ConversationStatus,
    val assignee: Assignee?,
    val unreadCount: Int,
    val lastMessage: Message?,
    /** The flow step the conversation waits on. */
    val flow: FlowStep?,
    val openedFrom: String?,
    /** Epoch milliseconds, UTC. */
    val createdAt: Long,
) {
    data class FlowStep(val flowId: String, val nodeId: String)
}

internal data class ConversationPage(val conversations: List<Conversation>, val nextCursor: String?)

/** A page of history, sorted by `seq`. */
internal data class MessagePage(val messages: List<Message>, val hasMore: Boolean)

/** POST /conversations: the new conversation with its first bot messages. */
internal data class ConversationWithMessages(val conversation: Conversation, val messages: List<Message>)

/** POST /flows/trigger. [conversation] is null when no flow is bound to the event. */
internal data class FlowTriggerResult(val started: Boolean, val conversation: ConversationWithMessages?)

internal data class MobileUser(
    val id: String,
    val anonymous: Boolean,
    val name: String?,
    val email: String?,
    val phone: String?,
    val language: String?,
    val customAttributes: Map<String, JsonElement>,
)

/** POST /uploads. */
internal data class UploadedFile(
    val uploadId: String,
    val url: String,
    val name: String,
    val size: Long,
    val mime: String,
)

/** The `error` of every failed request. New codes may appear within v1; a client then goes by the status. */
internal data class ServerError(
    val code: String,
    val message: String,
    val requestId: String?,
    /** `validation_failed`: field → reason. */
    val fields: Map<String, String>,
)
