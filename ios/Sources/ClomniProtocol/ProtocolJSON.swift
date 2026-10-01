import Foundation

/// The protocol's entry points. None of them throws or traps: input they cannot use gives nil (or, inside a message,
/// `.unknown` content), and a line goes to `ClomniLog`.
package enum ProtocolJSON {

    /// A message as REST or the socket sends it; nil when its envelope is unusable (no id, seq, sender …).
    package static func parseMessage(_ data: Data) -> Message? {
        decode(data, "message") { try Message($0) }
    }

    /// The same, for a message inside a larger response that was already decoded.
    package static func parseMessage(_ json: JSONValue) -> Message? {
        read(json, "message") { try Message($0) }
    }

    package static func parseEvent(_ data: Data) -> RealtimeEvent? {
        decode(data, "event") { try RealtimeEvent($0) }
    }

    /// A text WebSocket frame.
    package static func parseEvent(_ text: String) -> RealtimeEvent? {
        parseEvent(Data(text.utf8))
    }

    /// A frame that was already decoded (to look at its `event` first, say).
    package static func parseEvent(_ json: JSONValue) -> RealtimeEvent? {
        read(json, "event") { try RealtimeEvent($0) }
    }

    /// nil only when the body is not a JSON object; every missing field takes its default.
    package static func parseConfig(_ data: Data) -> MessengerConfig? {
        decode(data, "config") { MessengerConfig($0) }
    }

    /// nil when the payload is not a Clomni push.
    package static func parsePush(_ data: Data) -> PushPayload? {
        decode(data, "push") { try PushPayload($0) }
    }

    /// Whether a push is Clomni's (`"clomni": "1"` next to `aps`), without reading the rest: the app's own pushes are
    /// none of the SDK's business.
    package static func isClomniPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["clomni"] as? String == "1"
    }

    /// A Clomni push this version can read. nil for the app's own pushes (quietly) and for a Clomni push it cannot
    /// read (with a log line).
    package static func clomniPush(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
        isClomniPush(userInfo) ? parsePush(userInfo) : nil
    }

    /// An APNs `userInfo`. Only the top-level scalars are read: the Clomni keys sit next to `aps`.
    package static func parsePush(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
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

    package static func parseClientMessage(_ data: Data) -> ClientMessage? {
        decode(data, "client message") { try ClientMessage($0) }
    }

    /// The request body for POST /v1/conversations/{id}/messages.
    package static func encode(_ message: ClientMessage) -> Data {
        encode(message.json)
    }

    /// Any request body.
    package static func encode(_ json: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // JSONValue always encodes (non-finite numbers become null), so the fallback is never taken.
        return (try? encoder.encode(json)) ?? Data()
    }

    /// Any JSON, for the parts of a response the protocol has no type for.
    package static func decode(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func decode<T>(_ data: Data, _ what: String, _ build: (JSONFields) throws -> T) -> T? {
        guard let json = decode(data) else {
            ClomniLog.warning("\(what): not JSON, dropped")
            return nil
        }
        return read(json, what, build)
    }

    static func read<T>(_ json: JSONValue, _ what: String, _ build: (JSONFields) throws -> T) -> T? {
        do {
            return try build(JSONFields(json, path: what))
        } catch {
            ClomniLog.warning("\(error); \(what) dropped")
            return nil
        }
    }
}
