import Foundation

// Response bodies of the Mobile API (protocol/openapi.yaml). A list drops an item it cannot read (with a log line)
// rather than failing the whole page.

/// POST /mobile/sessions and /mobile/sessions/refresh.
package struct MobileSession: Sendable, Equatable {
    package let sessionToken: String
    package let expiresAt: Date
    /// Single-use: a refresh answers with the next one.
    package let refreshToken: String
    package let userId: String
    package let anonymous: Bool
    package let language: String?
    package let wsUrl: URL
}

package struct Conversation: Sendable, Equatable, Identifiable {
    package let id: String
    package var status: ConversationStatus
    package var assignee: Assignee?
    package var unreadCount: Int
    package var lastMessage: Message?
    /// The flow step the conversation waits on.
    package var flow: FlowStep?
    package let openedFrom: String?
    package let createdAt: Date

    package struct FlowStep: Sendable, Equatable {
        package let flowId: String
        package let nodeId: String
    }
}

package struct ConversationPage: Sendable, Equatable {
    package let conversations: [Conversation]
    package let nextCursor: String?
}

/// A page of history, sorted by `seq`.
package struct MessagePage: Sendable, Equatable {
    package let messages: [Message]
    package let hasMore: Bool
}

/// POST /conversations: the new conversation with its first bot messages.
package struct ConversationWithMessages: Sendable, Equatable {
    package let conversation: Conversation
    package let messages: [Message]
}

/// POST /flows/trigger. `conversation` is nil when no flow is bound to the event.
package struct FlowTriggerResult: Sendable, Equatable {
    package let started: Bool
    package let conversation: ConversationWithMessages?
}

package struct MobileUser: Sendable, Equatable {
    package let id: String
    package let anonymous: Bool
    package let name: String?
    package let email: String?
    package let phone: String?
    package let language: String?
    package let customAttributes: [String: JSONValue]
}

/// POST /uploads.
package struct UploadedFile: Sendable, Equatable {
    package let uploadId: String
    package let url: URL
    package let name: String
    package let size: Int
    package let mime: String
}

/// The `error` object every failed request carries. New codes may appear within v1; a client goes by the status then.
package struct ServerError: Sendable, Equatable {
    package let code: String
    package let message: String
    package let requestId: String?
    /// `validation_failed`: field → reason.
    package let fields: [String: String]
}

// MARK: - Parsing

extension JSONFields {
    /// A required array whose unreadable items are dropped with a log line.
    func items<T>(_ key: String, _ item: (JSONFields) throws -> T) throws -> [T] {
        guard let values = self[key]?.arrayValue else { throw ParseError("\(path).\(key): expected an array") }
        return values.enumerated().compactMap { index, value in
            do {
                return try item(JSONFields(value, path: "\(path).\(key)[\(index)]"))
            } catch {
                ProtocolLog.write("\(error); item dropped")
                return nil
            }
        }
    }
}

extension MobileSession {
    init(_ f: JSONFields) throws {
        let user = try f.object("user")
        sessionToken = try f.string("session_token")
        expiresAt = try f.date("expires_at")
        refreshToken = try f.string("refresh_token")
        userId = try user.string("id")
        anonymous = try user.bool("anonymous")
        language = user.optionalString("language")
        wsUrl = try f.url("ws_url")
    }

    var json: JSONValue {
        ["session_token": .string(sessionToken), "expires_at": .string(ISOTime.format(expiresAt)),
         "refresh_token": .string(refreshToken), "ws_url": .string(wsUrl.absoluteString),
         "user": ["id": .string(userId), "anonymous": .bool(anonymous), "language": .orNull(language)]]
    }
}

extension Conversation {
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        status = ConversationStatus(rawValue: try f.string("status")) ?? .unknown
        assignee = try f.optionalObject("assignee").map { try Assignee($0) }
        unreadCount = f.optionalInt("unread_count") ?? 0
        lastMessage = try f.optionalObject("last_message").map { try Message($0) }
        flow = f.optionalObject("flow").flatMap { step in
            guard let flowId = step.optionalString("flow_id"), let nodeId = step.optionalString("node_id") else { return nil }
            return FlowStep(flowId: flowId, nodeId: nodeId)
        }
        openedFrom = f.optionalString("opened_from")
        createdAt = try f.date("created_at")
    }

    var json: JSONValue {
        ["id": .string(id), "status": .string(status.rawValue), "assignee": assignee?.json ?? .null,
         "unread_count": .int(unreadCount), "last_message": lastMessage?.json ?? .null,
         "flow": flow.map { ["flow_id": .string($0.flowId), "node_id": .string($0.nodeId)] } ?? .null,
         "opened_from": .orNull(openedFrom), "created_at": .string(ISOTime.format(createdAt))]
    }
}

extension Assignee {
    var json: JSONValue {
        var fields: [String: JSONValue] = ["name": .string(name), "avatar_url": .orNull(avatarUrl?.absoluteString)]
        fields["online"] = online.map(JSONValue.bool)
        return .object(fields)
    }
}

extension ConversationWithMessages {
    init(_ f: JSONFields) throws {
        conversation = try Conversation(f.object("conversation"))
        messages = try f.items("messages") { try Message($0) }
    }
}

extension MobileUser {
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        anonymous = try f.bool("anonymous")
        name = f.optionalString("name")
        email = f.optionalString("email")
        phone = f.optionalString("phone")
        language = f.optionalString("language")
        customAttributes = f["custom_attributes"]?.objectValue ?? [:]
    }
}

extension UploadedFile {
    init(_ f: JSONFields) throws {
        uploadId = try f.string("upload_id")
        url = try f.url("url")
        name = try f.string("name")
        size = try f.int("size")
        mime = try f.string("mime")
    }
}

extension ServerError {
    init(_ f: JSONFields) throws {
        let error = try f.object("error")
        code = try error.string("code")
        message = error.optionalString("message") ?? ""
        requestId = error.optionalString("request_id")
        fields = (error["fields"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
    }
}

// Kept on disk by the SDK (session in the Keychain, conversations in its cache) in the wire format.

extension MobileSession: Codable {
    package init(from decoder: Decoder) throws {
        self = try MobileSession(JSONFields(JSONValue(from: decoder), path: "session"))
    }

    package func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }
}

extension Conversation: Codable {
    package init(from decoder: Decoder) throws {
        self = try Conversation(JSONFields(JSONValue(from: decoder), path: "conversation"))
    }

    package func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }
}

extension ProtocolJSON {
    package static func parseSession(_ data: Data) -> MobileSession? {
        decode(data, "session") { try MobileSession($0) }
    }

    package static func parseConversation(_ data: Data) -> Conversation? {
        decode(data, "conversation") { try Conversation($0) }
    }

    /// GET /conversations.
    package static func parseConversationPage(_ data: Data) -> ConversationPage? {
        decode(data, "conversations") {
            ConversationPage(conversations: try $0.items("conversations") { try Conversation($0) },
                             nextCursor: $0.optionalString("next_cursor"))
        }
    }

    /// GET /conversations/{id}/messages.
    package static func parseMessagePage(_ data: Data) -> MessagePage? {
        decode(data, "messages") {
            MessagePage(messages: try $0.items("messages") { try Message($0) }, hasMore: $0.optionalBool("has_more") ?? false)
        }
    }

    /// POST /conversations.
    package static func parseConversationWithMessages(_ data: Data) -> ConversationWithMessages? {
        decode(data, "conversation") { try ConversationWithMessages($0) }
    }

    /// POST /flows/trigger.
    package static func parseFlowTrigger(_ data: Data) -> FlowTriggerResult? {
        decode(data, "flow trigger") {
            FlowTriggerResult(started: try $0.bool("started"),
                              conversation: try $0.optionalObject("conversation").map { try ConversationWithMessages($0) })
        }
    }

    package static func parseUser(_ data: Data) -> MobileUser? {
        decode(data, "user") { try MobileUser($0) }
    }

    package static func parseUpload(_ data: Data) -> UploadedFile? {
        decode(data, "upload") { try UploadedFile($0) }
    }

    /// nil for a body that is not an `Error` (a proxy's HTML page, say); the status then says what happened.
    package static func parseServerError(_ data: Data) -> ServerError? {
        guard let json = decode(data) else { return nil }
        return try? ServerError(JSONFields(json, path: "error"))
    }
}
