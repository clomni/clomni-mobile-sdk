import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// What a form's fields hold while the user fills them in, checked here before anything is sent (the server checks
/// again; its `validation_failed` fields land in the same place).
package enum FormInput {
    /// field key → error text; empty when the form can be sent.
    package static func errors(_ form: MessageContent.Form, values: [String: String],
                              strings: ClomniStrings) -> [String: String] {
        var errors: [String: String] = [:]
        for field in form.fields {
            let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                if field.required {
                    errors[field.key] = field.type == .select ? strings[.chooseOption] : strings[.fieldRequired]
                }
                continue
            }
            if let limit = field.maxLength, value.count > limit {
                errors[field.key] = strings.format(.tooLong, limit)
                continue
            }
            switch field.type {
            case .email where !isEmail(value):
                errors[field.key] = strings[.invalidEmail]
            case .phone where phone(value, defaultCountry: field.defaultCountry) == nil:
                errors[field.key] = strings[.invalidPhone]
            case .number where number(value) == nil:
                errors[field.key] = strings[.invalidNumber]
            case .select where !field.options.contains(where: { $0.value == value }):
                errors[field.key] = strings[.chooseOption]
            case .date where !isDate(value):
                errors[field.key] = strings[.fieldRequired]
            default:
                break
            }
        }
        return errors
    }

    /// The `values` of a form_submit: every field, numbers as numbers, phones in international form, an empty
    /// optional field as "".
    package static func payload(_ form: MessageContent.Form, values: [String: String]) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [:]
        for field in form.fields {
            let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch field.type {
            case .number: payload[field.key] = number(value).map(JSONValue.number) ?? .string(value)
            case .phone: payload[field.key] = .string(phone(value, defaultCountry: field.defaultCountry) ?? value)
            default: payload[field.key] = .string(value)
            }
        }
        return payload
    }

    /// What the logged-in user's known details fill in before they type: name, email, phone by the field's key or
    /// type.
    package static func prefill(_ form: MessageContent.Form, known: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for field in form.fields {
            let byType: String? = field.type == .email ? known["email"] : field.type == .phone ? known["phone"] : nil
            if let value = known[field.key] ?? byType, !value.isEmpty { values[field.key] = value }
        }
        return values
    }

    /// A submitted form as label · value lines, in the form's order.
    package static func submittedLines(_ form: MessageContent.Form) -> [(label: String, value: String)] {
        guard let submitted = form.submitted else { return [] }
        return form.fields.compactMap { field in
            guard let value = submitted[field.key] else { return nil }
            let text: String
            switch value {
            case .string(let string): text = field.options.first { $0.value == string }?.label ?? string
            case .number: text = value.intValue.map(String.init) ?? value.doubleValue.map { "\($0)" } ?? ""
            case .bool(let flag): text = flag ? "✓" : "–"
            default: text = ""
            }
            return text.isEmpty ? nil : (field.label, text)
        }
    }

    /// "+994501234567" from "+994 50 123 45 67", "050 123 45 67" or "501234567" with default country AZ; nil when
    /// it cannot be a phone number.
    package static func phone(_ raw: String, defaultCountry: String?) -> String? {
        let international = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let allowed = CharacterSet(charactersIn: "0123456789+ -().")
        guard raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        var digits = raw.filter(\.isNumber)
        if !international {
            if digits.hasPrefix("00") {
                digits.removeFirst(2)
            } else if let code = defaultCountry.flatMap({ callingCodes[$0.uppercased()] }) {
                while digits.hasPrefix("0") { digits.removeFirst() }
                digits = code + digits
            } else {
                return nil
            }
        }
        return (8...15).contains(digits.count) ? "+" + digits : nil
    }

    static func number(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ".")).flatMap { $0.isFinite ? $0 : nil }
    }

    static func isEmail(_ value: String) -> Bool {
        value.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// The date picker's "yyyy-MM-dd".
    static func isDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// The countries the panel offers as a phone field's `default_country`.
    static let callingCodes: [String: String] = [
        "AZ": "994", "TR": "90", "RU": "7", "KZ": "7", "GE": "995", "UA": "380", "UZ": "998", "BY": "375", "KG": "996",
        "TJ": "992", "TM": "993", "AM": "374", "IR": "98", "AE": "971", "SA": "966", "QA": "974", "IL": "972",
        "US": "1", "CA": "1", "GB": "44", "DE": "49", "FR": "33", "IT": "39", "ES": "34", "NL": "31", "PL": "48",
        "CN": "86", "IN": "91",
    ]
}
