package ai.clomni.messenger.core

import ai.clomni.messenger.protocol.Sender

/** What changed, for the screens to redraw. */
internal sealed interface ClomniChange {
    data object Session : ClomniChange

    data object Config : ClomniChange

    /** The published news. */
    data object News : ClomniChange

    data object Conversations : ClomniChange

    /** Messages or pending messages of one conversation. */
    data class Messages(val conversationId: String) : ClomniChange

    data class Unread(val total: Int) : ClomniChange

    data class Typing(val conversationId: String, val sender: Sender, val isTyping: Boolean) : ClomniChange

    /** A message from [sender] came over the socket, new or a copy already held: they are no longer typing it. */
    data class Arrived(val conversationId: String, val sender: Sender) : ClomniChange

    data class Read(val conversationId: String, val upToSeq: Long) : ClomniChange

    /** The first message of draft [draftId] created conversation [conversationId] on the server. */
    data class Started(val draftId: String, val conversationId: String) : ClomniChange
}
