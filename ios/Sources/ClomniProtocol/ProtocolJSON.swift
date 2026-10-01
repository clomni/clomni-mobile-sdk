import Foundation

/// The protocol's entry points. None of them throws or traps: input they cannot use gives nil (or, inside a message,
/// `.unknown` content), and a line goes to `logHandler`.
public enum ProtocolJSON {
    /// Receives one line for everything that was dropped or downgraded. The SDK sets it from its log level; nil (the
    /// default) discards the lines.
    public static var logHandler: (@Sendable (String) -> Void)? {
        get { ProtocolLog.shared.handler }
        set { ProtocolLog.shared.handler = newValue }
    }

    /// A message as REST or the socket sends it; nil when its envelope is unusable (no id, seq, sender …).
    public static func parseMessage(_ data: Data) -> Message? {
        decode(data, "message") { try Message($0) }
    }

    /// The same, for a message inside a larger response that was already decoded.
    public static func parseMessage(_ json: JSONValue) -> Message? {
        read(json, "message") { try Message($0) }
    }

    public static func parseEvent(_ data: Data) -> RealtimeEvent? {
        decode(data, "event") { try RealtimeEvent($0) }
    }

    /// A text WebSocket frame.
    public static func parseEvent(_ text: String) -> RealtimeEvent? {
        parseEvent(Data(text.utf8))
    }

    /// nil only when the body is not a JSON object; every missing field takes its default.
    public static func parseConfig(_ data: Data) -> MessengerConfig? {
        decode(data, "config") { MessengerConfig($0) }
    }

    /// nil when the payload is not a Clomni push.
    public static func parsePush(_ data: Data) -> PushPayload? {
        decode(data, "push") { try PushPayload($0) }
    }

    /// An APNs `userInfo`. Only the top-level scalars are read: the Clomni keys sit next to `aps`.
    public static func parsePush(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
        var fields: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let key = key.base as? String,
                  value is String || value is NSNumber || value is Int || value is Double || value is NSNull else { continue }
            fields[key] = value
        }
        // data(withJSONObject:) raises an Objective-C exception, not a Swift error, on what it cannot write.
        guard JSONSerialization.isValidJSONObject(fields), let data = try? JSONSerialization.data(withJSONObject: fields)
        else { return nil }
        return parsePush(data)
    }

    public static func parseClientMessage(_ data: Data) -> ClientMessage? {
        decode(data, "client message") { try ClientMessage($0) }
    }

    /// The request body for POST /v1/conversations/{id}/messages.
    public static func encode(_ message: ClientMessage) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // JSONValue always encodes (non-finite numbers become null), so the fallback is never taken.
        return (try? encoder.encode(message.json)) ?? Data()
    }

    /// Any JSON, for the parts of a response the protocol has no type for.
    public static func decode(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func decode<T>(_ data: Data, _ what: String, _ build: (JSONFields) throws -> T) -> T? {
        guard let json = decode(data) else {
            ProtocolLog.write("\(what): not JSON, dropped")
            return nil
        }
        return read(json, what, build)
    }

    private static func read<T>(_ json: JSONValue, _ what: String, _ build: (JSONFields) throws -> T) -> T? {
        do {
            return try build(JSONFields(json, path: what))
        } catch {
            ProtocolLog.write("\(error); \(what) dropped")
            return nil
        }
    }
}

final class ProtocolLog: @unchecked Sendable {
    static let shared = ProtocolLog()

    private let lock = NSLock()
    private var _handler: (@Sendable (String) -> Void)?

    var handler: (@Sendable (String) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _handler = newValue
        }
    }

    static func write(_ line: String) {
        shared.handler?("[ClomniProtocol] \(line)")
    }
}
