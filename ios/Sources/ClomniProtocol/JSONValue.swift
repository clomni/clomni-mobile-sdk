import Foundation

/// Raw JSON: the content of an unknown message type, form values, custom data.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The number when it is a whole one that fits in `Int`; 5 and 5.0 both read as 5.
    public var intValue: Int? {
        guard case .number(let value) = self, value.rounded(.towardZero) == value,
              value >= -9.0e15, value <= 9.0e15 else { return nil }
        return Int(value)
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

extension JSONValue {
    /// An app's own values as JSON (`Clomni.startFlow(event, data: ["ride_id": ride.id])`): strings, numbers,
    /// booleans, arrays, string-keyed dictionaries and nil. nil for anything else, such as a Date.
    public init?(any value: Any?) {
        guard let value else { self = .null; return }
        switch value {
        case let json as JSONValue: self = json
        case let string as String: self = .string(string)
        case let flag as Bool: self = .bool(flag)
        case let number as Int: self = .number(Double(number))
        case let number as Double: self = .number(number)
        case let number as Float: self = .number(Double(number))
        case is NSNull: self = .null
        case let array as [Any?]:
            var items: [JSONValue] = []
            for item in array {
                guard let json = JSONValue(any: item) else { return nil }
                items.append(json)
            }
            self = .array(items)
        case let dictionary as [String: Any?]:
            var fields: [String: JSONValue] = [:]
            for (key, item) in dictionary {
                guard let json = JSONValue(any: item) else { return nil }
                fields[key] = json
            }
            self = .object(fields)
        default:
            return nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out as integers (5, not 5.0); JSON has no NaN or infinity.
            if let int = intValue {
                try container.encode(int)
            } else if value.isFinite {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
