package ai.clomni.messenger.protocol

/**
 * A message as the server sends it (REST and WebSocket), `protocol/schema/message.json`.
 *
 * Ids are opaque: never parse them or sort by them; [seq] orders a conversation.
 * When [content] is [MessageContent.Unknown] the message is shown as a bot bubble with [fallbackText].
 */
internal data class Message(
    val id: String,
    /** UUID the client sent with its own message; replaces the optimistic bubble. Null for everything else. */
    val clientId: String?,
    val conversationId: String,
    /** The wire type as sent (`text`, `quick_replies`, … or one this SDK does not know). */
    val type: String,
    val sender: Sender,
    /** Epoch milliseconds, UTC. */
    val createdAt: Long,
    val seq: Long,
    /** `az`, `en` or `ru`; kept as sent. */
    val lang: String,
    val flow: FlowRef?,
    val content: MessageContent,
    val fallbackText: String,
    /** The message this one answers, quoted over its bubble; null when it answers none. */
    val replyTo: ReplyRef? = null,
)

/** `reply_to`: the quoted message as the server describes it, so it shows even when it is not loaded here. */
internal data class ReplyRef(
    val id: String,
    /** Null when the quoted message is not the user's to see or no longer exists. */
    val sender: Sender?,
    /** One line of plain text; null when the message was deleted or is not there (the quote reads quote_deleted). */
    val excerpt: String?,
    /** text, image, file, or a kind added later (shown as text). */
    val kind: String,
)

internal data class Sender(
    val type: SenderType,
    val id: String? = null,
    val name: String? = null,
    val avatarUrl: String? = null,
)

internal enum class SenderType(internal val wire: String) {
    BOT("bot"),
    OPERATOR("operator"),
    USER("user"),
    SYSTEM("system"),

    /** A sender type added to the protocol after this SDK was built. */
    UNKNOWN("unknown"),
    ;

    internal companion object {
        fun from(wire: String?): SenderType = entries.firstOrNull { it.wire == wire && it != UNKNOWN } ?: UNKNOWN
    }
}

/** The flow node a message came from. [interactive] false: its buttons are disabled. */
internal data class FlowRef(
    val flowId: String,
    val nodeId: String,
    val version: Int?,
    val interactive: Boolean,
)
