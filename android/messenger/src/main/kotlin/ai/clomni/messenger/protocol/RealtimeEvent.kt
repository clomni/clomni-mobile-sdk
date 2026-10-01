package ai.clomni.messenger.protocol

/** A WebSocket frame `{event, data, ts}` (`protocol/schema/event.json`). */
public data class RealtimeEvent(
    val event: String,
    val data: Payload,
    /** Epoch milliseconds, UTC; null when missing or not a date-time. */
    val ts: Long?,
) {
    /** An unknown event, or a known one whose data is broken, is [Unknown] and is ignored by the client. */
    public sealed interface Payload {
        /** Fill the gaps since the last `seq` (GET messages?after_seq=…). */
        public data class Ready(val userId: String, val heartbeatSec: Int) : Payload

        /** Replaces the optimistic bubble when [Message.clientId] matches, otherwise is appended. */
        public data class MessageCreated(val message: Message) : Payload

        /** Replaces the message with the same id. */
        public data class MessageUpdated(val message: Message) : Payload

        /** The indicator hides by itself 8 s after the last `isTyping = true`. */
        public data class Typing(val conversationId: String, val sender: Sender, val isTyping: Boolean) : Payload

        public data class Read(val conversationId: String, val upToSeq: Long, val by: SenderType) : Payload

        public data class ConversationUpdated(val update: ConversationUpdate) : Payload

        /** Total unread messages of the user: the badge on the customer's own button. */
        public data class UnreadChanged(val total: Int) : Payload

        /** Reload the config (GET /mobile/config with If-None-Match). */
        public data class ConfigChanged(val etag: String) : Payload

        public data class Unknown(val name: String) : Payload
    }

    public data class ConversationUpdate(
        val id: String,
        val status: ConversationStatus,
        /** Null while no operator has the conversation. */
        val assignee: Assignee?,
        val unreadCount: Int?,
    )
}

/** bot → queued → open → closed; a closed conversation goes back to bot when the user writes again. */
public enum class ConversationStatus(internal val wire: String) {
    BOT("bot"),
    QUEUED("queued"),
    OPEN("open"),
    CLOSED("closed"),

    /** A status added to the protocol after this SDK was built. */
    UNKNOWN("unknown"),
    ;

    internal companion object {
        fun from(wire: String): ConversationStatus =
            entries.firstOrNull { it.wire == wire && it != UNKNOWN } ?: UNKNOWN
    }
}

/** The operator a conversation is assigned to. */
public data class Assignee(val name: String, val avatarUrl: String?, val online: Boolean?)
