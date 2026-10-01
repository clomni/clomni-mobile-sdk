import Foundation

/// The content of a message, by its `type`. The payload types are nested here rather than top level, because
/// `Button`, `Form` and `Image` would otherwise clash with SwiftUI's in every app that imports the SDK.
package enum MessageContent: Sendable, Equatable {
    case text(String)
    case quickReplies(QuickReplies)
    case image(Image)
    case file(File)
    case form(Form)
    case system(System)
    case card([CardItem])
    case rating(Rating)
    /// A type this SDK does not know, or a known type whose content is broken: shown through `fallbackText`.
    case unknown(type: String, raw: JSONValue)
}

extension MessageContent {
    /// Flow buttons. Titles arrive whole, however long; the UI wraps a long one to two lines.
    package struct QuickReplies: Sendable, Equatable {
        package let text: String?
        package let buttons: [Button]
        package let layout: QuickRepliesLayout
        /// The composer is hidden while this message waits for a button.
        package let inputDisabled: Bool
        /// A back button follows the others; it sends `ClientMessage.Content.back(replyTo:)`.
        package let allowBack: Bool
    }

    package struct Button: Sendable, Equatable, Identifiable {
        package let id: String
        package let title: String
        /// Shown before the title, e.g. a flag emoji.
        package let icon: String?
        /// Opaque: sent back as is in the button reply.
        package let payload: String
    }

    package enum QuickRepliesLayout: String, Sendable, Equatable {
        case vertical
        case chips
    }

    package struct Image: Sendable, Equatable {
        package let url: URL
        package let thumbUrl: URL?
        /// Known dimensions reserve the bubble's space before the image loads.
        package let width: Int?
        package let height: Int?
        package let caption: String?

        package init(url: URL, thumbUrl: URL? = nil, width: Int? = nil, height: Int? = nil, caption: String? = nil) {
            self.url = url
            self.thumbUrl = thumbUrl
            self.width = width
            self.height = height
            self.caption = caption
        }
    }

    package struct File: Sendable, Equatable {
        package let url: URL
        package let name: String
        /// Bytes.
        package let size: Int
        package let mime: String

        package init(url: URL, name: String, size: Int, mime: String) {
            self.url = url
            self.name = name
            self.size = size
            self.mime = mime
        }
    }

    package struct Form: Sendable, Equatable {
        package let text: String?
        package let formId: String
        package let fields: [FormField]
        package let submitTitle: String
        /// The values once sent; the form is then read-only.
        package let submitted: [String: JSONValue]?
    }

    package struct FormField: Sendable, Equatable {
        package let key: String
        package let type: FormFieldType
        package let label: String
        package let required: Bool
        package let maxLength: Int?
        /// ISO 3166 code for a phone field, e.g. "AZ".
        package let defaultCountry: String?
        package let placeholder: String?
        /// The choices of a select field (at least one); empty for the other types.
        package let options: [Option]

        package struct Option: Sendable, Equatable {
            package let value: String
            package let label: String
        }
    }

    /// An unknown field type reads as `.text`.
    package enum FormFieldType: String, Sendable, Equatable {
        case text, textarea, phone, email, number, select, date
    }

    /// Centred grey text without a bubble.
    package struct System: Sendable, Equatable {
        package let event: SystemEvent
        package let text: String
        /// Queue position, for `.waitingInQueue`.
        package let position: Int?
    }

    /// An unknown event is shown by its text alone.
    package enum SystemEvent: Sendable, Equatable {
        case operatorJoined
        case assignedToTeam
        case conversationClosed
        case conversationReopened
        case waitingInQueue
        case unknown(String)

        init(_ raw: String) {
            switch raw {
            case "operator_joined": self = .operatorJoined
            case "assigned_to_team": self = .assignedToTeam
            case "conversation_closed": self = .conversationClosed
            case "conversation_reopened": self = .conversationReopened
            case "waiting_in_queue": self = .waitingInQueue
            default: self = .unknown(raw)
            }
        }
    }

    package struct CardItem: Sendable, Equatable {
        package let imageUrl: URL?
        package let title: String
        package let subtitle: String?
        package let buttons: [CardButton]
    }

    /// Either sends `payload` back as a button reply or opens `url`.
    package struct CardButton: Sendable, Equatable, Identifiable {
        package let id: String
        package let title: String
        package let payload: String?
        package let url: URL?
    }

    package struct Rating: Sendable, Equatable {
        package let text: String
        package let scale: RatingScale
        package let comment: RatingComment
        package let submitted: [String: JSONValue]?
    }

    /// An unknown scale cannot be drawn, so it turns the whole message into `.unknown`.
    package enum RatingScale: String, Sendable, Equatable {
        case emoji5 = "emoji_5"
        case star5 = "star_5"
    }

    /// Whether the rating asks for a comment. An unknown value reads as `.optional`.
    package enum RatingComment: String, Sendable, Equatable {
        case hidden = "none"
        case optional
        case required
    }
}

// MARK: - Parsing

extension MessageContent {
    /// Reads `json` as the content of a message of `type`. Never fails: an unknown type or broken content gives
    /// `.unknown`, with a line to `ProtocolJSON.logHandler`.
    package init(type: String, json: JSONValue) {
        self.init(type: type, json: json, messageId: nil)
    }

    init(type: String, json: JSONValue, messageId: String?) {
        let prefix = messageId.map { "\($0): " } ?? ""
        do {
            let f = try JSONFields(json, path: type)
            switch type {
            case "text": self = .text(try f.string("text"))
            case "quick_replies": self = .quickReplies(try QuickReplies(f))
            case "image": self = .image(try Image(f))
            case "file": self = .file(try File(f))
            case "form": self = .form(try Form(f))
            case "system": self = .system(try System(f))
            case "card": self = .card(try f.nonEmptyArray("cards") { try CardItem($0) })
            case "rating": self = .rating(try Rating(f))
            default:
                ProtocolLog.write("\(prefix)unknown type \"\(type)\", shown as fallback_text")
                self = .unknown(type: type, raw: json)
            }
        } catch {
            ProtocolLog.write("\(prefix)\(error); shown as fallback_text")
            self = .unknown(type: type, raw: json)
        }
    }
}

extension MessageContent.QuickReplies {
    init(_ f: JSONFields) throws {
        text = f.optionalString("text")
        // A message that locks the composer with no button to press would leave the user stuck.
        buttons = try f.nonEmptyArray("buttons") { try MessageContent.Button($0) }
        layout = f.optionalString("layout").flatMap(MessageContent.QuickRepliesLayout.init(rawValue:)) ?? .vertical
        inputDisabled = f.optionalBool("input_disabled") ?? false
        allowBack = f.optionalBool("allow_back") ?? false
    }
}

extension MessageContent.Button {
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        title = try f.string("title")
        icon = f.optionalString("icon")
        payload = try f.string("payload")
    }
}

extension MessageContent.Image {
    init(_ f: JSONFields) throws {
        // A zero size would divide by zero when the UI reserves the aspect ratio.
        self.init(url: try f.url("url"), thumbUrl: f.optionalURL("thumb_url"),
                  width: f.optionalInt("width").flatMap { $0 > 0 ? $0 : nil },
                  height: f.optionalInt("height").flatMap { $0 > 0 ? $0 : nil }, caption: f.optionalString("caption"))
    }
}

extension MessageContent.File {
    init(_ f: JSONFields) throws {
        self.init(url: try f.url("url"), name: try f.string("name"), size: try f.int("size"), mime: try f.string("mime"))
    }
}

extension MessageContent.Form {
    init(_ f: JSONFields) throws {
        text = f.optionalString("text")
        formId = try f.string("form_id")
        fields = try f.nonEmptyArray("fields") { try MessageContent.FormField($0) }
        submitTitle = try f.string("submit_title")
        submitted = f["submitted"]?.objectValue
    }
}

extension MessageContent.FormField {
    init(_ f: JSONFields) throws {
        key = try f.string("key")
        type = MessageContent.FormFieldType(rawValue: try f.string("type")) ?? .text
        label = try f.string("label")
        required = f.optionalBool("required") ?? false
        maxLength = f.optionalInt("max_length")
        defaultCountry = f.optionalString("default_country")
        placeholder = f.optionalString("placeholder")
        options = try type == .select ? f.nonEmptyArray("options") { try Option($0) } : []
    }
}

extension MessageContent.FormField.Option {
    init(_ f: JSONFields) throws {
        value = try f.string("value")
        label = try f.string("label")
    }
}

extension MessageContent.System {
    init(_ f: JSONFields) throws {
        event = MessageContent.SystemEvent(try f.string("event"))
        text = try f.string("text")
        position = f.optionalInt("position")
    }
}

extension MessageContent.CardItem {
    init(_ f: JSONFields) throws {
        imageUrl = f.optionalURL("image_url")
        title = try f.string("title")
        subtitle = f.optionalString("subtitle")
        buttons = try f.contains("buttons") ? f.array("buttons") { try MessageContent.CardButton($0) } : []
    }
}

extension MessageContent.CardButton {
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        title = try f.string("title")
        payload = f.optionalString("payload")
        url = f.optionalURL("url")
        if payload == nil && url == nil { throw ParseError("\(f.path): expected a payload or a url") }
    }
}

extension MessageContent.Rating {
    init(_ f: JSONFields) throws {
        text = try f.string("text")
        let scale = try f.string("scale")
        guard let known = MessageContent.RatingScale(rawValue: scale) else {
            throw ParseError("\(f.path).scale: unknown scale \"\(scale)\"")
        }
        self.scale = known
        comment = f.optionalString("comment").map { MessageContent.RatingComment(rawValue: $0) ?? .optional } ?? .hidden
        submitted = f["submitted"]?.objectValue
    }
}
