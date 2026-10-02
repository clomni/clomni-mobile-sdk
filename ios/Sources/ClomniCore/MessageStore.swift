import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// Conversations and messages as this device knows them. A message is kept once by its id, however it arrived (REST,
/// socket, both), and messages are in `seq` order. Saved to disk so the next launch shows them at once.
struct MessageStore: Codable, Equatable {
    private(set) var conversations: [String: Conversation] = [:]
    private(set) var messages: [String: [Message]] = [:]
    var unreadTotal = 0
    /// The highest seq the operator has read, per conversation.
    private(set) var readUpTo: [String: Int] = [:]
    /// Messages whose buttons were used on this device; they stay disabled while the server's update is on its way.
    private(set) var answered: Set<String> = []

    func messages(in conversationId: String) -> [Message] {
        messages[conversationId] ?? []
    }

    func lastSeq(in conversationId: String) -> Int? {
        messages[conversationId]?.last?.seq
    }

    func message(_ id: String, in conversationId: String) -> Message? {
        messages[conversationId]?.first { $0.id == id }
    }

    /// Newest activity first.
    var sortedConversations: [Conversation] {
        conversations.values.sorted {
            ($0.lastMessage?.createdAt ?? $0.createdAt, $0.id) > ($1.lastMessage?.createdAt ?? $1.createdAt, $1.id)
        }
    }

    /// Adds a message or replaces the copy with its id (`message.updated`). With `detectGap`, a message that skips
    /// ahead of the newest one known returns that newest seq: 40 then 42 returns 40, and 41 is to be fetched.
    @discardableResult
    mutating func insert(_ message: Message, detectGap: Bool = false) -> Int? {
        var list = messages[message.conversationId] ?? []
        var gap: Int?
        if let index = list.firstIndex(where: { $0.id == message.id }) {
            list[index] = message
            list.sort(by: Self.inOrder)
        } else {
            if detectGap, let newest = list.last?.seq, message.seq > newest + 1 { gap = newest }
            list.insert(message, at: list.firstIndex { Self.inOrder(message, $0) } ?? list.endIndex)
        }
        messages[message.conversationId] = list
        if var conversation = conversations[message.conversationId],
           (conversation.lastMessage?.seq ?? Int.min) <= message.seq {
            conversation.lastMessage = message
            conversations[message.conversationId] = conversation
        }
        return gap
    }

    /// The seq after which the first hole in a conversation's messages starts (1, 2, 4 → 2), if there is one.
    func firstGap(in conversationId: String) -> Int? {
        let seqs = messages(in: conversationId).map(\.seq)
        return zip(seqs, seqs.dropFirst()).first { $1 > $0 + 1 }?.0
    }

    mutating func upsert(_ conversation: Conversation) {
        var conversation = conversation
        // A list fetched a moment ago must not take back a message the socket has delivered since.
        if let known = conversations[conversation.id]?.lastMessage, (conversation.lastMessage?.seq ?? Int.min) < known.seq {
            conversation.lastMessage = known
        }
        conversations[conversation.id] = conversation
    }

    /// `conversation.updated`; a conversation not known yet arrives with the next list.
    mutating func apply(_ update: RealtimeEvent.ConversationUpdate) {
        guard var conversation = conversations[update.id] else { return }
        conversation.status = update.status
        conversation.assignee = update.assignee
        if let unread = update.unreadCount { conversation.unreadCount = unread }
        conversations[update.id] = conversation
    }

    mutating func markReadByOperator(_ conversationId: String, upToSeq: Int) {
        readUpTo[conversationId] = max(readUpTo[conversationId] ?? 0, upToSeq)
    }

    mutating func markSeen(_ conversationId: String) {
        conversations[conversationId]?.unreadCount = 0
    }

    mutating func markAnswered(_ messageId: String) {
        answered.insert(messageId)
    }

    /// Only the latest interactive message of a conversation has live buttons, and only until it is answered.
    func canAnswer(_ message: Message) -> Bool {
        guard message.flow?.interactive == true, !answered.contains(message.id) else { return false }
        let latest = messages(in: message.conversationId).last { $0.flow?.interactive == true }
        return latest.map { $0.id == message.id } ?? true
    }

    /// What goes to disk: the newest `limit` messages of each conversation.
    func trimmed(to limit: Int) -> MessageStore {
        var copy = self
        copy.messages = messages.mapValues { Array($0.suffix(limit)) }
        return copy
    }

    private static func inOrder(_ a: Message, _ b: Message) -> Bool {
        (a.seq, a.id) < (b.seq, b.id)
    }
}

/// A message on its way to the server, shown as the user's bubble until the server's copy replaces it.
package struct PendingMessage: Sendable, Equatable, Identifiable, Codable {
    package enum State: String, Sendable, Codable {
        case sending
        /// Three attempts failed, or the server refused it: "Göndərilmədi · Yenidən cəhd et".
        case failed
    }

    /// A draft's id (`ClomniEngine.draftConversation`) until the server has created the conversation.
    package internal(set) var conversationId: String
    /// A draft's `opened_from`, for creating it.
    package internal(set) var openedFrom: String?
    package internal(set) var message: ClientMessage
    /// What the bubble shows: the text, the button's title, the caption. nil for the back button and a form, whose
    /// labels are the UI's own.
    package let preview: String?
    package let createdAt: Date
    package internal(set) var state = State.sending
    package internal(set) var attempts = 0
    /// The server's reason when it refused the message, e.g. `validation_failed` with `fields`.
    package internal(set) var errorCode: String?
    package internal(set) var fields: [String: String] = [:]
    /// A file the user attached: kept on this device until the server has the message.
    package internal(set) var upload: PendingUpload?

    package var id: String { message.clientId }
}

/// An attached file on its way: uploaded first (POST /uploads), then sent as an `attachment` message.
package struct PendingUpload: Sendable, Equatable, Codable {
    package let fileName: String
    package let mime: String
    /// Bytes.
    package let size: Int
    /// The file's name in the SDK's cache directory.
    let storedAs: String
    /// Set once the upload succeeded; a retry then only sends the message.
    package internal(set) var uploadId: String?
}

/// Pending messages in the order they were written; kept on disk until the server has each one.
struct Outbox: Codable, Equatable {
    private(set) var entries: [PendingMessage] = []

    var next: PendingMessage? {
        entries.first { $0.state == .sending }
    }

    func entries(in conversationId: String) -> [PendingMessage] {
        entries.filter { $0.conversationId == conversationId }
    }

    func entry(_ clientId: String) -> PendingMessage? {
        entries.first { $0.id == clientId }
    }

    mutating func add(_ entry: PendingMessage) {
        entries.append(entry)
    }

    @discardableResult
    mutating func remove(_ clientId: String) -> PendingMessage? {
        guard let index = entries.firstIndex(where: { $0.id == clientId }) else { return nil }
        return entries.remove(at: index)
    }

    /// A draft's messages, to the conversation the server created for it.
    mutating func retarget(_ draft: String, to conversationId: String) {
        for index in entries.indices where entries[index].conversationId == draft {
            entries[index].conversationId = conversationId
        }
    }

    mutating func update(_ clientId: String, _ change: (inout PendingMessage) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == clientId }) else { return }
        change(&entries[index])
    }
}

/// Files under Application Support/Clomni/<app id>. Writes are atomic; a file that cannot be read is treated as absent.
struct DiskCache: Sendable {
    let directory: URL

    static func standard(appId: String) -> DiskCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return DiskCache(directory: base.appendingPathComponent("Clomni", isDirectory: true)
            .appendingPathComponent(appId, isDirectory: true))
    }

    func read(_ name: String) -> Data? {
        IOProbe.note("read \(name)")
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    func write(_ data: Data?, _ name: String) {
        IOProbe.note("write \(name)")
        let url = directory.appendingPathComponent(name)
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        } catch {
            ClomniLog.warning("could not write \(name): \(error)")
        }
    }

    func contains(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        read(name).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        write(try? JSONEncoder().encode(value), name)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
