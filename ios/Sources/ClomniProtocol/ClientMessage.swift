import Foundation

/// A client → server message: the body of POST /v1/conversations/{id}/messages (protocol/schema/client-message.json).
package struct ClientMessage: Sendable, Equatable {
    /// UUID v4. A retry sends the same one, and the server never handles one client id twice.
    package let clientId: String
    package let content: Content
    /// A text or an attachment answering a message (swipe or long press): its server id.
    package let replyTo: String?
    /// An attachment that is a voice message: its length and waveform, as recorded.
    package let voice: Voice?

    package init(clientId: String = ClientMessage.newClientId(), content: Content, replyTo: String? = nil, voice: Voice? = nil) {
        self.clientId = clientId
        self.content = content
        self.replyTo = replyTo
        self.voice = voice
    }

    /// What goes with a voice message's attachment (protocol client-message.json attachment.duration_ms, .waveform).
    package struct Voice: Sendable, Equatable {
        package let durationMs: Int?
        /// 0–100 each (the SDKs send 64).
        package let waveform: [Int]?

        package init(durationMs: Int?, waveform: [Int]?) {
            self.durationMs = durationMs
            self.waveform = waveform
        }
    }

    package enum Content: Sendable, Equatable {
        /// Up to 4000 characters; the composer never sends an empty one.
        case text(String)
        /// A flow button. `payload` goes back exactly as the server sent it.
        case buttonReply(replyTo: String, buttonId: String, payload: String)
        case formSubmit(replyTo: String, formId: String, values: [String: JSONValue])
        /// `uploadId` comes from POST /v1/uploads.
        case attachment(uploadId: String, caption: String?)
        case ratingSubmit(replyTo: String, score: Int, comment: String?)

        /// The back button under quick replies with `allowBack`.
        package static func back(replyTo: String) -> Content {
            .buttonReply(replyTo: replyTo, buttonId: "back", payload: "nav:back")
        }
    }

    /// The wire `type`.
    package var type: String {
        switch content {
        case .text: return "text"
        case .buttonReply: return "button_reply"
        case .formSubmit: return "form_submit"
        case .attachment: return "attachment"
        case .ratingSubmit: return "rating_submit"
        }
    }

    package static func newClientId() -> String {
        UUID().uuidString.lowercased()
    }
}

extension ClientMessage {
    var json: JSONValue {
        var content: [String: JSONValue]
        switch self.content {
        case .text(let text):
            content = ["text": .string(text)]
        case let .buttonReply(replyTo, buttonId, payload):
            content = ["reply_to": .string(replyTo), "button_id": .string(buttonId), "payload": .string(payload)]
        case let .formSubmit(replyTo, formId, values):
            content = ["reply_to": .string(replyTo), "form_id": .string(formId), "values": .object(values)]
        case let .attachment(uploadId, caption):
            content = ["upload_id": .string(uploadId), "caption": caption.map(JSONValue.string) ?? .null]
        case let .ratingSubmit(replyTo, score, comment):
            content = ["reply_to": .string(replyTo), "score": .number(Double(score)),
                       "comment": comment.map(JSONValue.string) ?? .null]
        }
        if let replyTo, type == "text" || type == "attachment" { content["reply_to"] = .string(replyTo) }
        if let voice, type == "attachment" {
            content["duration_ms"] = voice.durationMs.map(JSONValue.int)
            content["waveform"] = voice.waveform.map { .array($0.map(JSONValue.int)) }
        }
        return ["client_id": .string(clientId), "type": .string(type), "content": .object(content)]
    }

    /// Reads a message back, e.g. one the outbox kept on disk.
    init(_ f: JSONFields) throws {
        let type = try f.string("type")
        let c = try f.object("content")
        switch type {
        case "text":
            content = .text(try c.string("text"))
        case "button_reply":
            content = .buttonReply(replyTo: try c.string("reply_to"), buttonId: try c.string("button_id"),
                                   payload: try c.string("payload"))
        case "form_submit":
            content = .formSubmit(replyTo: try c.string("reply_to"), formId: try c.string("form_id"),
                                  values: try c.object("values").fields)
        case "attachment":
            content = .attachment(uploadId: try c.string("upload_id"), caption: c.optionalString("caption"))
        case "rating_submit":
            content = .ratingSubmit(replyTo: try c.string("reply_to"), score: try c.int("score"),
                                    comment: c.optionalString("comment"))
        default:
            throw ParseError("\(f.path).type: unknown client message type \"\(type)\"")
        }
        clientId = try f.string("client_id")
        replyTo = type == "text" || type == "attachment" ? c.optionalString("reply_to") : nil
        let duration = c.optionalInt("duration_ms")
        let waveform = c["waveform"].flatMap(MessageContent.Audio.levels)
        voice = type == "attachment" && (duration != nil || waveform != nil) ? Voice(durationMs: duration, waveform: waveform) : nil
    }
}
