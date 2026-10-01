import Foundation

/// A server → client message (protocol/schema/message.json), from REST or the socket.
///
/// Ids are opaque: never parse them or sort by them; order is `seq`. An unknown `type`, or content that does not
/// match its type, arrives as `.unknown` and is shown through `fallbackText`.
public struct Message: Sendable, Equatable, Identifiable {
    public let id: String
    /// The UUID the client sent with its own message; it matches the optimistic bubble to the server's copy.
    public let clientId: String?
    public let conversationId: String
    public let type: String
    public let sender: Sender
    public let createdAt: Date
    public let seq: Int
    public let lang: String
    public let flow: FlowRef?
    public let content: MessageContent
    public let fallbackText: String

    public init(id: String, clientId: String? = nil, conversationId: String, type: String, sender: Sender,
                createdAt: Date, seq: Int, lang: String, flow: FlowRef? = nil, content: MessageContent,
                fallbackText: String) {
        self.id = id
        self.clientId = clientId
        self.conversationId = conversationId
        self.type = type
        self.sender = sender
        self.createdAt = createdAt
        self.seq = seq
        self.lang = lang
        self.flow = flow
        self.content = content
        self.fallbackText = fallbackText
    }
}

public enum SenderType: String, Sendable, Equatable {
    case bot
    case `operator`
    case user
    case system
    case unknown
}

public struct Sender: Sendable, Equatable {
    public let type: SenderType
    public let id: String?
    public let name: String?
    public let avatarUrl: URL?

    public init(type: SenderType, id: String? = nil, name: String? = nil, avatarUrl: URL? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

/// The flow node a message came from. `interactive == false` disables the message's buttons.
public struct FlowRef: Sendable, Equatable {
    public let flowId: String
    public let nodeId: String
    public let version: Int?
    public let interactive: Bool

    public init(flowId: String, nodeId: String, version: Int? = nil, interactive: Bool) {
        self.flowId = flowId
        self.nodeId = nodeId
        self.version = version
        self.interactive = interactive
    }
}

extension Message {
    init(_ f: JSONFields) throws {
        let id = try f.string("id")
        let type = try f.string("type")
        guard let content = f["content"], content.objectValue != nil else {
            throw ParseError("\(f.path).content: expected an object")
        }
        let conversationId = try f.string("conversation_id")
        let sender = try Sender(f.object("sender"))
        let createdAt = try f.date("created_at")
        let seq = try f.int("seq")
        let lang = try f.string("lang")
        let fallbackText = try f.string("fallback_text")
        var flow: FlowRef?
        if let value = f["flow"] {
            do {
                flow = try FlowRef(JSONFields(value, path: "\(f.path).flow"))
            } catch {
                ProtocolLog.write("\(id): \(error); shown without its flow")
            }
        }
        // Content last, so a message rejected for its envelope does not also log about its content.
        self.init(id: id, clientId: f.optionalString("client_id"), conversationId: conversationId, type: type,
                  sender: sender, createdAt: createdAt, seq: seq, lang: lang, flow: flow,
                  content: MessageContent(type: type, json: content, messageId: id), fallbackText: fallbackText)
    }
}

extension Sender {
    init(_ f: JSONFields) throws {
        self.init(type: SenderType(rawValue: try f.string("type")) ?? .unknown, id: f.optionalString("id"),
                  name: f.optionalString("name"), avatarUrl: f.optionalURL("avatar_url"))
    }
}

extension FlowRef {
    init(_ f: JSONFields) throws {
        self.init(flowId: try f.string("flow_id"), nodeId: try f.string("node_id"), version: f.optionalInt("version"),
                  interactive: try f.bool("interactive"))
    }
}
