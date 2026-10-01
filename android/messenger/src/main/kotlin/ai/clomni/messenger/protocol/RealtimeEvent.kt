package ai.clomni.messenger.protocol

/**
 * A WebSocket frame `{event, data, ts}` (`protocol/schema/event.json`), by its event.
 * An event this SDK does not know, or a known one with broken data, is [Unknown] and is ignored.
 */
public sealed interface RealtimeEvent {

    /** Fill the gaps since the last `seq` (GET messages?after_seq=…). */
    public data class Ready(val userId: String, val heartbeatSec: Int) : RealtimeEvent

    /** Replaces the optimistic bubble when [Message.clientId] matches, otherwise is appended. */
    public data class MessageCreated(val message: Message) : RealtimeEvent

    /** Replaces the message with the same id. */
    public data class MessageUpdated(val message: Message) : RealtimeEvent

    /** The indicator hides by itself 8 s after the last `isTyping = true`. */
    public data class Typing(val conversationId: String, val sender: Sender, val isTyping: Boolean) : RealtimeEvent

    /** [by] is [SenderType.USER] or [SenderType.OPERATOR]. */
    public data class Read(val conversationId: String, val upToSeq: Long, val by: SenderType) : RealtimeEvent

    public data class ConversationUpdated(
        val id: String,
        val status: ConversationStatus,
        val assignee: Assignee?,
        val unreadCount: Int?,
    ) : RealtimeEvent

    /** Total unread messages of the user: the badge on the customer's own button. */
    public data class UnreadChanged(val total: Int) : RealtimeEvent

    /** Reload the config (GET /mobile/config with If-None-Match). */
    public data class ConfigChanged(val etag: String) : RealtimeEvent

    public data class Unknown(val name: String) : RealtimeEvent
}

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
public data class Assignee(val name: String, val avatarUrl: String?, val online: Boolean)
