package ai.clomni.messenger.presentation

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.store.PendingMessage
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.util.UUID
import java.util.concurrent.Future

/** What the conversation screen reads and does; `ClomniEngine` is one, tests use a fake. */
internal interface ChatDataSource {
    val config: MessengerConfig?

    /** The socket is connected and delivering: no need to ask for new messages by hand. */
    val isLive: Boolean

    fun conversation(id: String): Conversation?

    fun refreshConversation(id: String): Future<Unit>

    fun messages(conversationId: String): List<Message>

    fun pending(conversationId: String): List<PendingMessage>

    fun canAnswer(message: Message): Boolean

    fun readByOperator(conversationId: String): Long?

    fun localFile(pending: PendingMessage): File?

    fun loadMessages(conversationId: String): Future<Unit>

    fun loadOlder(conversationId: String): Future<Boolean>

    fun markRead(conversationId: String): Future<Unit>

    fun setTyping(isTyping: Boolean, conversationId: String): Future<Unit>

    /** [replyTo]: the message the user answers, quoted over the new one. */
    fun sendText(text: String, conversationId: String, replyTo: String? = null): Future<PendingMessage>

    fun reply(message: Message, button: MessageContent.Button): Future<PendingMessage>

    fun goBack(message: Message): Future<PendingMessage>

    fun submitForm(message: Message, values: Map<String, JsonElement>): Future<PendingMessage>

    fun sendFile(
        data: ByteArray,
        fileName: String,
        mime: String,
        caption: String?,
        conversationId: String,
        replyTo: String? = null,
    ): Future<PendingMessage>

    fun retry(clientId: String): Future<Unit>

    /** A new conversation to write in; the server has it only once its first message goes (`ClomniChange.Started`). */
    fun draft(openedFrom: String?): String

    fun observe(handler: (ClomniChange) -> Unit): UUID

    fun stopObserving(token: UUID)
}
