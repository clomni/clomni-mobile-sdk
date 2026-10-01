package ai.clomni.messenger.protocol

import java.util.UUID

/**
 * Body of POST /v1/conversations/{id}/messages (`protocol/schema/client-message.json`), encoded by
 * [ProtocolJson.encode]. [clientId] is a UUID v4: a retry sends the same message with the same id, and the server
 * handles one id only once.
 */
public sealed interface ClientMessage {
    public val clientId: String

    /** False when the server would refuse it (empty or too long text, score out of 1–5, …): do not send it. */
    public val isValid: Boolean

    public data class Text(
        val text: String,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val isValid: Boolean get() = validId(clientId) && text.isNotEmpty() && fits(text)
    }

    /** A flow button; `nav:back` for "← Back". [payload] is the button's own, passed through unchanged. */
    public data class ButtonReply(
        val replyTo: String,
        val buttonId: String,
        val payload: String,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val isValid: Boolean
            get() = validId(clientId) && replyTo.isNotEmpty() && buttonId.isNotEmpty() && payload.isNotEmpty()
    }

    public data class FormSubmit(
        val replyTo: String,
        val formId: String,
        /** By [FormField.key], as the user typed or chose them. */
        val values: Map<String, String>,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val isValid: Boolean get() = validId(clientId) && replyTo.isNotEmpty() && formId.isNotEmpty()
    }

    /** A file sent before with POST /v1/uploads. */
    public data class Attachment(
        val uploadId: String,
        val caption: String? = null,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val isValid: Boolean
            get() = validId(clientId) && uploadId.isNotEmpty() && (caption == null || fits(caption))
    }

    public data class RatingSubmit(
        val replyTo: String,
        val score: Int,
        val comment: String? = null,
        override val clientId: String = newClientId(),
    ) : ClientMessage {
        override val isValid: Boolean
            get() = validId(clientId) && replyTo.isNotEmpty() && score in 1..5 && (comment == null || fits(comment))
    }

    public companion object {
        /** Longest text, caption or comment the server accepts, in characters (code points). */
        public const val MAX_TEXT_LENGTH: Int = 4000

        public fun newClientId(): String = UUID.randomUUID().toString()

        private fun validId(id: String) = id.length in 1..64

        private fun fits(text: String) = text.codePointCount(0, text.length) <= MAX_TEXT_LENGTH
    }
}
