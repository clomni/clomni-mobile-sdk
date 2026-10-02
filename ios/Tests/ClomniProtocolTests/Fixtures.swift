import Foundation
import XCTest
@testable import ClomniProtocol

/// The protocol folder at the repository root, found from this file's own path so the tests run unchanged on Linux
/// and macOS.
enum Fixtures {
    static let protocolDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ClomniProtocolTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("protocol")

    /// Each folder's index.json names the schema of every file in it.
    static let folders = ["fixtures", "examples/brief"]

    struct Entry: Decodable {
        let file: String
        let schema: String
        let valid: Bool?

        var isValid: Bool { valid != false }
    }

    static func entries(_ folder: String) throws -> [Entry] {
        try JSONDecoder().decode([Entry].self, from: data("index.json", in: folder))
    }

    static func data(_ file: String, in folder: String = "fixtures") throws -> Data {
        try Data(contentsOf: protocolDir.appendingPathComponent(folder).appendingPathComponent(file))
    }

    static func json(_ file: String, in folder: String = "fixtures") throws -> JSONValue {
        try XCTUnwrap(ProtocolJSON.decode(data(file, in: folder)), "\(file) is not JSON")
    }

    static func message(_ file: String, in folder: String = "fixtures") throws -> Message {
        try XCTUnwrap(ProtocolJSON.parseMessage(data(file, in: folder)), "\(file) did not parse")
    }

    static func event(_ file: String) throws -> RealtimeEvent {
        try XCTUnwrap(ProtocolJSON.parseEvent(data(file)), "\(file) did not parse")
    }
}

/// Collects what the parser logs while a test runs.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _lines
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        _lines.append(line)
    }

    func contains(_ text: String) -> Bool {
        lines.contains { $0.contains(text) }
    }
}

class ProtocolTestCase: XCTestCase {
    var log = LogCapture()

    override func setUp() {
        super.setUp()
        let log = LogCapture()
        self.log = log
        ClomniLog.handler = { _, line in log.append(line) }
        ClomniLog.level = .debug
    }

    override func tearDown() {
        ClomniLog.reset()
        super.tearDown()
    }
}

extension JSONValue {
    /// A copy with `key` set (or removed, for nil) in this object, or in the object at `path` inside it.
    func setting(_ key: String, _ value: JSONValue?, at path: [String] = []) -> JSONValue {
        guard case .object(var fields) = self else { return self }
        if let first = path.first {
            fields[first] = (fields[first] ?? [:]).setting(key, value, at: Array(path.dropFirst()))
        } else {
            fields[key] = value
        }
        return .object(fields)
    }
}

extension MessageContent {
    /// The wire type a case stands for.
    var kind: String {
        switch self {
        case .text: return "text"
        case .quickReplies: return "quick_replies"
        case .image: return "image"
        case .file: return "file"
        case .form: return "form"
        case .system: return "system"
        case .card: return "card"
        case .rating: return "rating"
        case .unknown: return "unknown"
        }
    }

    var quickReplies: QuickReplies? {
        if case .quickReplies(let value) = self { return value }
        return nil
    }

    var form: Form? {
        if case .form(let value) = self { return value }
        return nil
    }

    var system: System? {
        if case .system(let value) = self { return value }
        return nil
    }

    var cards: [CardItem]? {
        if case .card(let value) = self { return value }
        return nil
    }
}

extension RealtimeEvent.Payload {
    /// The event name a case stands for.
    var kind: String {
        switch self {
        case .ready: return "ready"
        case .messageCreated: return "message.created"
        case .messageUpdated: return "message.updated"
        case .typing: return "typing"
        case .read: return "read"
        case .conversationUpdated: return "conversation.updated"
        case .unreadChanged: return "unread.changed"
        case .configChanged: return "config.changed"
        case .unknown: return "unknown"
        }
    }
}
