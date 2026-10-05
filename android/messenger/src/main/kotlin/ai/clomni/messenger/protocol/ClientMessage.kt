package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonElement
import java.util.UUID

/**
 * Body of POST /v1/conversations/{id}/messages (`protocol/schema/client-message.json`), encoded by
 * [ProtocolJson.encode] and read back (e.g. from the outbox on disk) by [ProtocolJson.parseClientMessage].
 */
internal sealed interface ClientMessage {
    /** UUID v4. A retry sends the same one, and the server never handles one client id twice. */
    val clientId: String

    /** The wire `type`. */
    val type: String

    /** Up to 4000 characters; the composer never sends an empty one. */
    data class Text(
        val text: String,
        override val clientId: String = newClientId(),
        /** The message the user answers (swipe or long press), by its server id. */
        val replyTo: String? = null,
    ) : ClientMessage {
        override val type: String get() = "text"
    }

    /** A flow button. [payload] goes back exactly as the server sent it. */
    data class ButtonReply(
        val replyTo: String,
        val buttonId: String,
        val payload: String,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "button_reply"
    }

    data class FormSubmit(
        val replyTo: String,
        val formId: String,
        /** By [MessageContent.FormField.key]. */
        val values: Map<String, JsonElement>,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "form_submit"
    }

    /** [uploadId] comes from POST /v1/uploads. */
    data class Attachment(
        val uploadId: String,
        val caption: String? = null,
        override val clientId: String = newClientId(),
        /** As for [Text.replyTo]. */
        val replyTo: String? = null,
    ) : ClientMessage {
        override val type: String get() = "attachment"
    }

    data class RatingSubmit(
        val replyTo: String,
        val score: Int,
        val comment: String? = null,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val type: String get() = "rating_submit"
    }

    companion object {
        fun newClientId(): String = UUID.randomUUID().toString()

        /** The back button under quick replies with `allowBack`. */
        fun back(replyTo: String, clientId: String = newClientId()): ButtonReply =
            ButtonReply(replyTo, buttonId = "back", payload = "nav:back", clientId = clientId)
    }
}
