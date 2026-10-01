import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// Everything the conversation screen shows (brief 8 · 7.4, 7.5, 7.6), decided here so the SwiftUI view only draws.
public struct ChatScreen: Sendable, Equatable {
    public let phase: HomeScreen.Phase
    public let header: ChatHeader
    public let items: [ChatItem]
    public let composer: ChatComposer
    /// The thin yellow strip under the header.
    public let offline: String?
    public let failure: HomeScreen.Failure?
    /// The newest incoming message, for VoiceOver to read out when it changes.
    public let announcement: Announcement?
}

public struct Announcement: Sendable, Equatable {
    public let id: String
    public let text: String
}

/// White bar with the bottom hairline: back arrow, who is answering, ✕.
public struct ChatHeader: Sendable, Equatable {
    public enum Lead: Sendable, Equatable {
        /// Up to three team avatars, 24 pt, overlapping.
        case team([URL])
        /// The operator, 28 pt, with the green dot while online.
        case person(ChatAvatar, online: Bool)
    }

    public let lead: Lead
    /// The brand, or the operator's name.
    public let title: String
    /// "Komanda da kömək edə bilər", the reply time while queued, "Apar · onlayn", or that it is after hours.
    public let subtitle: String
    public let backLabel: String
    public let closeLabel: String
}

public struct ChatAvatar: Sendable, Equatable {
    public let url: URL?
    public let initial: String
    /// The bot is drawn in the brand colour while it has no picture.
    public let isBot: Bool
}

public enum ChatItem: Sendable, Equatable, Identifiable {
    /// "Bu gün 10:30": before the first message and after a pause of more than an hour.
    case time(id: String, text: String)
    case bubble(Bubble)
    /// Centred grey text without a bubble, with small avatars: "Leyla söhbətə qoşuldu".
    case system(SystemLine)
    /// The live buttons of the latest flow step.
    case replies(QuickReplyBlock)
    case typing(TypingLine)

    public var id: String {
        switch self {
        case .time(let id, _): return id
        case .bubble(let bubble): return bubble.id
        case .system(let line): return line.id
        case .replies(let block): return "replies-\(block.messageId)"
        case .typing: return "typing"
        }
    }
}

public struct Bubble: Sendable, Equatable, Identifiable {
    public enum Side: Sendable, Equatable { case incoming, outgoing }

    /// Where the bubble stands in a run of one sender's messages; the corners where bubbles meet are 5 pt.
    public enum Position: Sendable, Equatable { case single, first, middle, last }

    public enum Body: Sendable, Equatable {
        case text([TextRun])
        case image(ImageBody)
        case file(FileBody)
        case form(FormCard)
    }

    public struct ImageBody: Sendable, Equatable {
        /// The thumbnail if there is one.
        public let url: URL?
        /// For full screen.
        public let fullUrl: URL?
        /// A picture the user is sending, before the server has it.
        public let localFile: URL?
        public let width: Double
        public let height: Double
        /// false: a placeholder of this size until the image loads.
        public let sizeKnown: Bool
        public let caption: [TextRun]?
    }

    public struct FileBody: Sendable, Equatable {
        public let name: String
        /// "182 KB"
        public let size: String
        public let symbol: String
        public let url: URL?
    }

    public struct Status: Sendable, Equatable {
        /// "Göndərilir", "Göndərildi", "Oxundu", "Göndərilmədi · Yenidən cəhd et".
        public let text: String
        public let isFailure: Bool
        /// The client id to send again when the failure is tapped.
        public let retryId: String?
    }

    public let id: String
    public let side: Side
    public let body: Body
    public let position: Position
    /// Next to the last bubble of an incoming run.
    public let avatar: ChatAvatar?
    /// Under the last bubble of an incoming run: "Clomni · Bot · indi", "Leyla · indi".
    public let meta: String?
    /// Under the user's message when it is the last one, or when it failed.
    public let status: Status?
    public let accessibilityLabel: String
}

public struct SystemLine: Sendable, Equatable {
    public let id: String
    public let text: String
    public let avatars: [ChatAvatar]
}

public struct QuickReplyBlock: Sendable, Equatable {
    public let messageId: String
    public let layout: MessageContent.QuickRepliesLayout
    public let buttons: [ReplyButton]
    /// "← Geri" (nav:back), drawn grey after the others.
    public let back: ReplyButton?
}

public struct ReplyButton: Sendable, Equatable, Identifiable {
    public let id: String
    /// The icon (a flag, say) and the title, as drawn; long titles wrap to two lines and end with "…".
    public let title: String
    public let accessibilityLabel: String
}

public struct TypingLine: Sendable, Equatable {
    public let avatar: ChatAvatar
    public let accessibilityLabel: String
}

/// A form in a bot bubble; read-only once sent ("Göndərildi") or when it is no longer the live step.
public struct FormCard: Sendable, Equatable {
    public struct Field: Sendable, Equatable, Identifiable {
        public let id: String
        public let type: MessageContent.FormFieldType
        public let label: String
        public let required: Bool
        public let placeholder: String?
        public let maxLength: Int?
        public let options: [MessageContent.FormField.Option]
        /// The logged-in user's known value, filled in before they type.
        public let initialValue: String
    }

    public struct Line: Sendable, Equatable {
        public let label: String
        public let value: String
    }

    public let messageId: String
    public let text: [TextRun]?
    public let fields: [Field]
    public let submitTitle: String
    public let readOnly: Bool
    /// What was sent, label by label.
    public let submitted: [Line]
    /// "Göndərildi" under a sent form.
    public let sentLabel: String?
}

public struct ChatComposer: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case open
        /// The step waits for a button: "Yuxarıdakı variantlardan birini seçin", no icons.
        case locked(String)
        /// "Söhbət bağlanıb · Yeni söhbət başlat"; writing anyway reopens it.
        case closed(text: String, action: String)
    }

    public let mode: Mode
    public let placeholder: String
    public let showsAttach: Bool
    public let showsEmoji: Bool
    /// Characters a message may have.
    public let limit: Int
    public let sendLabel: String
    public let attachLabel: String
    public let emojiLabel: String
}

/// What the conversation screen is built from.
public struct ChatSnapshot: Sendable, Equatable {
    public var config: MessengerConfig?
    public var conversation: Conversation?
    /// In seq order.
    public var messages: [Message] = []
    public var pending: [PendingMessage] = []
    /// The files of pending attachments, by client id.
    public var localFiles: [String: URL] = [:]
    /// Messages whose buttons or form are live.
    public var answerable: Set<String> = []
    /// The highest seq the operator has read.
    public var readUpTo: Int?
    /// Who is typing, while the indicator shows.
    public var typing: Sender?
    public var load = MessengerSnapshot.Load.loading
    public var isOffline = false
    /// The user's details for prefilling forms: name, email, phone.
    public var known: [String: String] = [:]

    public init(config: MessengerConfig? = nil, conversation: Conversation? = nil, messages: [Message] = []) {
        self.config = config
        self.conversation = conversation
        self.messages = messages
    }
}
