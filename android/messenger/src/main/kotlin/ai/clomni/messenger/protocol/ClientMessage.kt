package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonElement
import java.util.UUID

/**
 * Body of POST /v1/conversations/{id}/messages (`protocol/schema/client-message.json`), encoded by
 * [ProtocolJson.encode] and read back (e.g. from the outbox on disk) by [ProtocolJson.parseClientMessage].
 */
public sealed interface ClientMessage {
    /** UUID v4. A retry sends the same one, and the server never handles one client id twice. */
    public val clientId: String

    /** The wire `type`. */
    public val type: String

    /** Up to 4000 characters; the composer never sends an empty one. */
    public data class Text(
        val text: String,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "text"
    }

    /** A flow button. [payload] goes back exactly as the server sent it. */
    public data class ButtonReply(
        val replyTo: String,
        val buttonId: String,
        val payload: String,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "button_reply"
    }

    public data class FormSubmit(
        val replyTo: String,
        val formId: String,
        /** By [MessageContent.FormField.key]. */
        val values: Map<String, JsonElement>,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "form_submit"
    }

    /** [uploadId] comes from POST /v1/uploads. */
    public data class Attachment(
        val uploadId: String,
        val caption: String? = null,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "attachment"
    }

    public data class RatingSubmit(
        val replyTo: String,
        val score: Int,
        val comment: String? = null,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "rating_submit"
    }

    public companion object {
        public fun newClientId(): String = UUID.randomUUID().toString()

        /** The back button under quick replies with `allowBack`. */
        public fun back(replyTo: String, clientId: String = newClientId()): ButtonReply =
            ButtonReply(replyTo, buttonId = "back", payload = "nav:back", clientId = clientId)
    }
}
