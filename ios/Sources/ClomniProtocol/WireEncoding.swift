import Foundation

// Models written back in their wire format, so the SDK can keep them on disk and read them with the same parser on
// the next launch. Fields the parser skipped are not written; reading the result gives back an equal value.

extension Message: Codable {
    public init(from decoder: Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let message = ProtocolJSON.parseMessage(json) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a message"))
        }
        self = message
    }

    public func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }

    var json: JSONValue {
        [
            "id": .string(id), "client_id": .orNull(clientId), "conversation_id": .string(conversationId),
            "type": .string(type), "sender": sender.json, "created_at": .string(ISOTime.format(createdAt)),
            "seq": .int(seq), "lang": .string(lang), "flow": flow?.json ?? .null, "content": content.json,
            "fallback_text": .string(fallbackText),
        ]
    }
}

extension ClientMessage: Codable {
    public init(from decoder: Decoder) throws {
        let json = try JSONValue(from: decoder)
        self = try ClientMessage(JSONFields(json, path: "client message"))
    }

    public func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }
}

extension Sender {
    var json: JSONValue {
        var fields: [String: JSONValue] = ["type": .string(type.rawValue)]
        fields["id"] = id.map(JSONValue.string)
        fields["name"] = name.map(JSONValue.string)
        fields["avatar_url"] = avatarUrl.map { .string($0.absoluteString) }
        return .object(fields)
    }
}

extension FlowRef {
    var json: JSONValue {
        var fields: [String: JSONValue] = ["flow_id": .string(flowId), "node_id": .string(nodeId),
                                           "interactive": .bool(interactive)]
        fields["version"] = version.map(JSONValue.int)
        return .object(fields)
    }
}

extension MessageContent {
    var json: JSONValue {
        switch self {
        case .text(let text):
            return ["text": .string(text)]
        case .quickReplies(let replies):
            var fields: [String: JSONValue] = [
                "buttons": .array(replies.buttons.map(\.json)), "layout": .string(replies.layout.rawValue),
                "input_disabled": .bool(replies.inputDisabled), "allow_back": .bool(replies.allowBack),
            ]
            fields["text"] = replies.text.map(JSONValue.string)
            return .object(fields)
        case .image(let image):
            return ["url": .string(image.url.absoluteString), "thumb_url": .orNull(image.thumbUrl?.absoluteString),
                    "width": image.width.map(JSONValue.int) ?? .null, "height": image.height.map(JSONValue.int) ?? .null,
                    "caption": .orNull(image.caption)]
        case .file(let file):
            return ["url": .string(file.url.absoluteString), "name": .string(file.name), "size": .int(file.size),
                    "mime": .string(file.mime)]
        case .form(let form):
            var fields: [String: JSONValue] = [
                "form_id": .string(form.formId), "fields": .array(form.fields.map(\.json)),
                "submit_title": .string(form.submitTitle), "submitted": form.submitted.map(JSONValue.object) ?? .null,
            ]
            fields["text"] = form.text.map(JSONValue.string)
            return .object(fields)
        case .system(let system):
            var fields: [String: JSONValue] = ["event": .string(system.event.rawValue), "text": .string(system.text)]
            fields["position"] = system.position.map(JSONValue.int)
            return .object(fields)
        case .card(let cards):
            return ["cards": .array(cards.map(\.json))]
        case .rating(let rating):
            return ["text": .string(rating.text), "scale": .string(rating.scale.rawValue),
                    "comment": .string(rating.comment.rawValue), "submitted": rating.submitted.map(JSONValue.object) ?? .null]
        case .unknown(_, let raw):
            return raw
        }
    }
}

extension MessageContent.Button {
    var json: JSONValue {
        ["id": .string(id), "title": .string(title), "icon": .orNull(icon), "payload": .string(payload)]
    }
}

extension MessageContent.FormField {
    var json: JSONValue {
        var fields: [String: JSONValue] = ["key": .string(key), "type": .string(type.rawValue), "label": .string(label),
                                           "required": .bool(required)]
        fields["max_length"] = maxLength.map(JSONValue.int)
        fields["default_country"] = defaultCountry.map(JSONValue.string)
        fields["placeholder"] = placeholder.map(JSONValue.string)
        if type == .select {
            fields["options"] = .array(options.map { ["value": .string($0.value), "label": .string($0.label)] })
        }
        return .object(fields)
    }
}

extension MessageContent.SystemEvent {
    var rawValue: String {
        switch self {
        case .operatorJoined: return "operator_joined"
        case .assignedToTeam: return "assigned_to_team"
        case .conversationClosed: return "conversation_closed"
        case .conversationReopened: return "conversation_reopened"
        case .waitingInQueue: return "waiting_in_queue"
        case .unknown(let raw): return raw
        }
    }
}

extension MessageContent.CardItem {
    var json: JSONValue {
        ["image_url": .orNull(imageUrl?.absoluteString), "title": .string(title), "subtitle": .orNull(subtitle),
         "buttons": .array(buttons.map(\.json))]
    }
}

extension MessageContent.CardButton {
    var json: JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id), "title": .string(title)]
        fields["payload"] = payload.map(JSONValue.string)
        fields["url"] = url.map { .string($0.absoluteString) }
        return .object(fields)
    }
}

extension JSONValue {
    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
    static func orNull(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
}
