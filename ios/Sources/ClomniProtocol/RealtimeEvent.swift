import Foundation

/// A WebSocket frame `{event, data, ts}` (protocol/schema/event.json).
package struct RealtimeEvent: Sendable, Equatable {
    package let event: String
    package let data: Payload
    package let ts: Date?

    /// An unknown event, or a known one whose data is broken, is `.unknown` and is ignored by the client.
    package enum Payload: Sendable, Equatable {
        case ready(userId: String, heartbeatSec: Int)
        case messageCreated(Message)
        case messageUpdated(Message)
        case typing(conversationId: String, sender: Sender, isTyping: Bool)
        case read(conversationId: String, upToSeq: Int, by: SenderType)
        case conversationUpdated(ConversationUpdate)
        case unreadChanged(total: Int)
        case configChanged(etag: String)
        case unknown(name: String)
    }

    package struct ConversationUpdate: Sendable, Equatable {
        package let id: String
        package let status: ConversationStatus
        /// nil while no operator has the conversation.
        package let assignee: Assignee?
        package let unreadCount: Int?
    }
}

/// bot → queued → open → closed; a closed conversation goes back to bot when the user writes again.
package enum ConversationStatus: String, Sendable, Equatable {
    case bot, queued, open, closed, unknown
}

package struct Assignee: Sendable, Equatable {
    package let name: String
    package let avatarUrl: URL?
    package let online: Bool?
}

extension RealtimeEvent {
    init(_ f: JSONFields) throws {
        event = try f.string("event")
        ts = f.optionalString("ts").flatMap(ISOTime.parse)
        do {
            data = try Payload(event: event, data: f["data"])
        } catch {
            ClomniLog.warning("\(event): \(error); event ignored")
            data = .unknown(name: event)
        }
    }
}

extension RealtimeEvent.Payload {
    init(event: String, data: JSONValue?) throws {
        let path = "\(event).data"
        switch event {
        case "ready":
            let f = try JSONFields(data, path: path)
            self = .ready(userId: try f.string("user_id"), heartbeatSec: try f.int("heartbeat_sec"))
        case "message.created": self = .messageCreated(try Message(JSONFields(data, path: path)))
        case "message.updated": self = .messageUpdated(try Message(JSONFields(data, path: path)))
        case "typing":
            let f = try JSONFields(data, path: path)
            let state = try f.string("state")
            guard state == "on" || state == "off" else { throw ParseError("\(path).state: expected on or off") }
            self = .typing(conversationId: try f.string("conversation_id"), sender: try Sender(f.object("sender")),
                           isTyping: state == "on")
        case "read":
            let f = try JSONFields(data, path: path)
            self = .read(conversationId: try f.string("conversation_id"), upToSeq: try f.int("up_to_seq"),
                         by: SenderType(rawValue: try f.string("by")) ?? .unknown)
        case "conversation.updated":
            self = .conversationUpdated(try RealtimeEvent.ConversationUpdate(JSONFields(data, path: path)))
        case "unread.changed": self = .unreadChanged(total: try JSONFields(data, path: path).int("total"))
        case "config.changed": self = .configChanged(etag: try JSONFields(data, path: path).string("etag"))
        default:
            ClomniLog.debug("unknown event \"\(event)\" ignored")
            self = .unknown(name: event)
        }
    }
}

extension RealtimeEvent.ConversationUpdate {
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        status = ConversationStatus(rawValue: try f.string("status")) ?? .unknown
        assignee = try f.optionalObject("assignee").map { try Assignee($0) }
        unreadCount = f.optionalInt("unread_count")
    }
}

extension Assignee {
    init(_ f: JSONFields) throws {
        name = try f.string("name")
        avatarUrl = f.optionalURL("avatar_url")
        online = f.optionalBool("online")
    }
}
