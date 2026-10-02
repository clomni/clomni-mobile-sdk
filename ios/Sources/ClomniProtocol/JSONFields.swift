import Foundation

/// Why a value could not be read. Internal: the public entry points turn it into nil or `.unknown` and a log line.
struct ParseError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Typed reads from one JSON object. A missing or mistyped required field throws; an optional one of the wrong type
/// reads as absent. Unknown keys are never looked at, which is how unknown fields are skipped.
struct JSONFields {
    let fields: [String: JSONValue]
    let path: String

    init(_ value: JSONValue?, path: String) throws {
        guard case .object(let fields)? = value else { throw ParseError("\(path): expected an object") }
        self.init(fields: fields, path: path)
    }

    init(fields: [String: JSONValue], path: String) {
        self.fields = fields
        self.path = path
    }

    subscript(key: String) -> JSONValue? {
        if case .null? = fields[key] { return nil }
        return fields[key]
    }

    /// Present and not null.
    func contains(_ key: String) -> Bool {
        if case .some = self[key] { return true }
        return false
    }

    private func required<T>(_ key: String, _ type: String, _ read: (JSONValue) -> T?) throws -> T {
        guard let value = self[key].flatMap(read) else { throw ParseError("\(path).\(key): expected \(type)") }
        return value
    }

    func string(_ key: String) throws -> String { try required(key, "a string") { $0.stringValue } }
    func int(_ key: String) throws -> Int { try required(key, "an integer") { $0.intValue } }
    func bool(_ key: String) throws -> Bool { try required(key, "a boolean") { $0.boolValue } }
    func url(_ key: String) throws -> URL { try required(key, "a URL") { $0.stringValue.flatMap(URL.init(string:)) } }
    func date(_ key: String) throws -> Date { try required(key, "an ISO 8601 time") { $0.stringValue.flatMap(ISOTime.parse) } }
    func object(_ key: String) throws -> JSONFields { try JSONFields(self[key], path: "\(path).\(key)") }

    /// A required array with at least one element, each read by `item`.
    func nonEmptyArray<T>(_ key: String, _ item: (JSONFields) throws -> T) throws -> [T] {
        let items = try array(key, item)
        if items.isEmpty { throw ParseError("\(path).\(key): expected at least one item") }
        return items
    }

    func array<T>(_ key: String, _ item: (JSONFields) throws -> T) throws -> [T] {
        guard let values = self[key]?.arrayValue else { throw ParseError("\(path).\(key): expected an array") }
        return try values.enumerated().map { try item(JSONFields($1, path: "\(path).\(key)[\($0)]")) }
    }

    func optionalString(_ key: String) -> String? { self[key]?.stringValue }
    func optionalInt(_ key: String) -> Int? { self[key]?.intValue }
    func optionalBool(_ key: String) -> Bool? { self[key]?.boolValue }
    func optionalURL(_ key: String) -> URL? { optionalString(key).flatMap(URL.init(string:)) }
    func optionalObject(_ key: String) -> JSONFields? { try? JSONFields(self[key], path: "\(path).\(key)") }
}

/// UTC ISO 8601 times, with or without milliseconds.
enum ISOTime {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func parse(_ string: String) -> Date? {
        (try? withFraction.parse(string)) ?? (try? whole.parse(string))
    }

    static func format(_ date: Date) -> String {
        withFraction.format(date)
    }
}
