import Foundation

/// The Clomni keys of a push (protocol/schema/push.json). On APNs they sit next to `aps`.
package struct PushPayload: Sendable, Equatable {
    /// "message" in v1.
    package let type: String
    package let conversationId: String
    package let messageId: String?
    package let title: String
    package let body: String
    package let avatarUrl: URL?
    package let unreadTotal: Int?
}

extension PushPayload {
    init(_ f: JSONFields) throws {
        guard f.optionalString("clomni") == "1" else { throw ParseError("not a Clomni push") }
        type = try f.string("type")
        conversationId = try f.string("conversation_id")
        messageId = f.optionalString("message_id")
        title = try f.string("title")
        body = try f.string("body")
        avatarUrl = f.optionalURL("avatar_url")
        // A relay that only carries strings (as FCM data does) may deliver the count as "3".
        unreadTotal = f.optionalInt("unread_total") ?? f.optionalString("unread_total").flatMap { Int($0) }
    }
}
