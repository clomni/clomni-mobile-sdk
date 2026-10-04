import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// Everything the conversation screen shows (brief 8 · 7.4, 7.5, 7.6), decided here so the SwiftUI view only draws.
package struct ChatScreen: Sendable, Equatable {
    package let phase: HomeScreen.Phase
    package let header: ChatHeader
    package let items: [ChatItem]
    package let composer: ChatComposer
    /// The thin yellow strip under the header.
    package let offline: String?
    package let failure: HomeScreen.Failure?
    /// The newest incoming message, for VoiceOver to read out when it changes.
    package let announcement: Announcement?
    /// What VoiceOver reads over the skeleton: "Yüklənir".
    package let loadingLabel: String
}

package struct Announcement: Sendable, Equatable {
    package let id: String
    package let text: String
}

/// White bar with the bottom hairline: back arrow, who is answering, ✕.
package struct ChatHeader: Sendable, Equatable {
    package enum Lead: Sendable, Equatable {
        /// Up to three team avatars, 24 pt, overlapping.
        case team([URL])
        /// The operator, 28 pt, with the green dot while online.
        case person(ChatAvatar, online: Bool)
    }

    package let lead: Lead
    /// The brand, or the operator's name.
    package let title: String
    /// header_subtitle (the reply time unless the panel wrote its own), the reply time while queued, "Apar ·
    /// onlayn", or that it is after hours.
    package let subtitle: String
    package let backLabel: String
    package let closeLabel: String
}

package struct ChatAvatar: Sendable, Equatable {
    package let url: URL?
    package let initial: String
    /// The bot is drawn in the brand colour while it has no picture.
    package let isBot: Bool
}

package enum ChatItem: Sendable, Equatable, Identifiable {
    /// "Bu gün 10:30": before the first message and after a pause of more than an hour.
    case time(id: String, text: String)
    case bubble(Bubble)
    /// Centred grey text without a bubble, with small avatars: "Leyla söhbətə qoşuldu".
    case system(SystemLine)
    /// The live buttons of the latest flow step.
    case replies(QuickReplyBlock)
    case typing(TypingLine)

    package var id: String {
        switch self {
        case .time(let id, _): return id
        case .bubble(let bubble): return bubble.id
        case .system(let line): return line.id
        case .replies(let block): return "replies-\(block.messageId)"
        case .typing: return "typing"
        }
    }
}

package struct Bubble: Sendable, Equatable, Identifiable {
    package enum Side: Sendable, Equatable { case incoming, outgoing }

    /// Where the bubble stands in a run of one sender's messages; the corners where bubbles meet are 5 pt.
    package enum Position: Sendable, Equatable { case single, first, middle, last }

    package enum Body: Sendable, Equatable {
        case text([TextRun])
        case image(ImageBody)
        case file(FileBody)
        case form(FormCard)
    }

    package struct ImageBody: Sendable, Equatable {
        /// The thumbnail if there is one.
        package let url: URL?
        /// For full screen.
        package let fullUrl: URL?
        /// A picture the user is sending, before the server has it.
        package let localFile: URL?
        package let width: Double
        package let height: Double
        /// false: a placeholder of this size until the image loads.
        package let sizeKnown: Bool
        package let caption: [TextRun]?
    }

    package struct FileBody: Sendable, Equatable {
        package let name: String
        /// "182 KB"
        package let size: String
        package let symbol: String
        package let url: URL?
    }

    package struct Status: Sendable, Equatable {
        /// "Göndərilir", "Göndərildi", "Oxundu", "Göndərilmədi · Yenidən cəhd et".
        package let text: String
        package let isFailure: Bool
        /// The client id to send again when the failure is tapped.
        package let retryId: String?
    }

    package let id: String
    package let side: Side
    package let body: Body
    package let position: Position
    /// Next to the last bubble of an incoming run.
    package let avatar: ChatAvatar?
    /// Over the first bubble of a bot's run, outside it (DESIGN-PASS-2 13): "Clomni · Bot".
    package let nameLine: String?
    /// Under the last bubble of an incoming run: "Leyla · indi"; a bot's run says only when, its name is above.
    package let meta: String?
    /// Under the user's message when it is the last one, or when it failed.
    package let status: Status?
    /// The message, who sent it and when, and its status unless that is a failure (which is a button of its own):
    /// "Siz, 10:30: Salam. Oxundu". VoiceOver reads the bubble, its meta line and its status as one element.
    package let accessibilityLabel: String
    /// What a tap does, where it is not plain: "Şəkli tam ekranda açır", "Faylı açır".
    package let accessibilityHint: String?
}

package struct SystemLine: Sendable, Equatable {
    package let id: String
    package let text: String
    package let avatars: [ChatAvatar]
}

package struct QuickReplyBlock: Sendable, Equatable {
    package let messageId: String
    package let layout: MessageContent.QuickRepliesLayout
    package let buttons: [ReplyButton]
    /// "← Geri" (nav:back), drawn grey after the others.
    package let back: ReplyButton?
}

package struct ReplyButton: Sendable, Equatable, Identifiable {
    package let id: String
    /// The icon (a flag, say) and the title, as drawn; long titles wrap to two lines and end with "…".
    package let title: String
    package let accessibilityLabel: String
}

package struct TypingLine: Sendable, Equatable {
    package let avatar: ChatAvatar
    package let accessibilityLabel: String
}

/// A form in a bot bubble; read-only once sent ("Göndərildi") or when it is no longer the live step.
package struct FormCard: Sendable, Equatable {
    package struct Field: Sendable, Equatable, Identifiable {
        package let id: String
        package let type: MessageContent.FormFieldType
        package let label: String
        package let required: Bool
        package let placeholder: String?
        package let maxLength: Int?
        package let options: [MessageContent.FormField.Option]
        /// "Ad, məcburi": the input's own label, so VoiceOver need not read the caption above it as well.
        package let accessibilityLabel: String
        /// The logged-in user's known value, filled in before they type.
        package let initialValue: String
    }

    package struct Line: Sendable, Equatable {
        package let label: String
        package let value: String
    }

    package let messageId: String
    package let text: [TextRun]?
    package let fields: [Field]
    package let submitTitle: String
    package let readOnly: Bool
    /// What was sent, label by label.
    package let submitted: [Line]
    /// "Göndərildi" under a sent form.
    package let sentLabel: String?

    /// What VoiceOver says when a submit comes back with errors: the first field's, "E-poçt: Email düzgün deyil".
    package func announcement(for errors: [String: String]) -> String? {
        fields.lazy.compactMap { field in errors[field.id].map { "\(field.label): \($0)" } }.first
    }
}

package struct ChatComposer: Sendable, Equatable {
    package enum Mode: Sendable, Equatable {
        case open
        /// The step waits for a choice and takes no text: no composer at all (operator, 2026-10-04).
        case locked(String)
        /// "Söhbət bağlanıb · Yeni söhbət başlat"; writing anyway reopens it.
        case closed(text: String, action: String)
    }

    package let mode: Mode
    package let placeholder: String
    package let showsAttach: Bool
    package let showsEmoji: Bool
    /// Characters a message may have.
    package let limit: Int
    package let sendLabel: String
    package let attachLabel: String
    package let emojiLabel: String
    /// The attachment sheet's rows: the photo library, the camera, any file; and the x on a picked file.
    package let mediaLabel: String
    package let cameraLabel: String
    package let fileLabel: String
    package let removeAttachmentLabel: String
}

/// What the conversation screen is built from.
package struct ChatSnapshot: Sendable, Equatable {
    package var config: MessengerConfig?
    package var conversation: Conversation?
    /// In seq order.
    package var messages: [Message] = []
    package var pending: [PendingMessage] = []
    /// The files of pending attachments, by client id.
    package var localFiles: [String: URL] = [:]
    /// Messages whose buttons or form are live.
    package var answerable: Set<String> = []
    /// The highest seq the operator has read.
    package var readUpTo: Int?
    /// Who is typing, while the indicator shows.
    package var typing: Sender?
    package var load = MessengerSnapshot.Load.loading
    package var isOffline = false
    /// The user's details for prefilling forms: name, email, phone.
    package var known: [String: String] = [:]

    package init(config: MessengerConfig? = nil, conversation: Conversation? = nil, messages: [Message] = []) {
        self.config = config
        self.conversation = conversation
        self.messages = messages
    }
}
