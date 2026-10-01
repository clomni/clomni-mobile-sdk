package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonPrimitive

/** The client-message fixtures, built the way the SDK builds them; each must encode to its file. */
object ClientMessageFixtures {
    val all: Map<String, ClientMessage> = mapOf(
        "fixtures/45-client-text.json" to ClientMessage.Text(
            text = "Gedişim bitmədi, pul çıxılmağa davam edir",
            clientId = "6f1c2c8e-1b2a-4c3d-8e9f-0a1b2c3d4e5f",
        ),
        "fixtures/46-client-button-reply.json" to ClientMessage.ButtonReply(
            replyTo = "msg_f09",
            buttonId = "o_s",
            payload = "node:S",
            clientId = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d",
        ),
        "fixtures/47-client-back.json" to ClientMessage.back("msg_f10", clientId = "1f2e3d4c-5b6a-4978-8a6b-5c4d3e2f1a0b"),
        "fixtures/48-client-form-submit.json" to ClientMessage.FormSubmit(
            replyTo = "msg_f19",
            formId = "frm_contact",
            values = mapOf(
                "name" to JsonPrimitive("Aysel Məmmədova"),
                "phone" to JsonPrimitive("+994501234567"),
                "email" to JsonPrimitive(""),
            ),
            clientId = "2a3b4c5d-6e7f-4801-9a2b-3c4d5e6f7a8b",
        ),
        "fixtures/49-client-attachment.json" to ClientMessage.Attachment(
            uploadId = "upl_77ab",
            caption = "Velosiped Nizami küçəsindədir",
            clientId = "3c2b1a09-8f7e-4d6c-9b5a-4f3e2d1c0b9a",
        ),
        "fixtures/51-client-button-end.json" to ClientMessage.ButtonReply(
            replyTo = "msg_f12",
            buttonId = "o_no",
            payload = "end",
            clientId = "5e6f7081-92a3-4b4c-8d5e-6f708192a3b4",
        ),
        "fixtures/52-client-rating.json" to ClientMessage.RatingSubmit(
            replyTo = "msg_f28",
            score = 5,
            comment = "Tez cavab verdiniz",
            clientId = "6f708192-a3b4-4c5d-9e6f-708192a3b4c5",
        ),
        "fixtures/93-invalid-client-text-empty.json" to ClientMessage.Text(
            text = "",
            clientId = "4d5e6f70-8192-4a3b-9c4d-5e6f708192a3",
        ),
        "examples/brief/s5-button-reply.json" to ClientMessage.ButtonReply(
            replyTo = "msg_8f21",
            buttonId = "b1",
            payload = "set_lang:az",
            clientId = "6f1c2c8e-...",
        ),
    )
}
