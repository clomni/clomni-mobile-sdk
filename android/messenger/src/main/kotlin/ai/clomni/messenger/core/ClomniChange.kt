package ai.clomni.messenger.core

import ai.clomni.messenger.protocol.Sender

/** What changed, for the screens to redraw. */
internal sealed interface ClomniChange {
    data object Session : ClomniChange

    data object Config : ClomniChange

    data object Conversations : ClomniChange

    /** Messages or pending messages of one conversation. */
    data class Messages(val conversationId: String) : ClomniChange

    data class Unread(val total: Int) : ClomniChange

    data class Typing(val conversationId: String, val sender: Sender, val isTyping: Boolean) : ClomniChange

    data class Read(val conversationId: String, val upToSeq: Long) : ClomniChange
}
