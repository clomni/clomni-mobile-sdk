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
    /// The capsule over the screen while offline (CM-077).
    package let offline: String?
    /// "Qoşuldu": the capsule's word for a second once the connection is back.
    package let connected: String
    package let failure: HomeScreen.Failure?
    /// The newest incoming message, for VoiceOver to read out when it changes.
    package let announcement: Announcement?
    /// What VoiceOver reads over the skeleton: "Yüklənir".
    package let loadingLabel: String
    /// A message's long-press menu: "Cavabla", "Kopyala".
    package let replyLabel: String
    package let copyLabel: String
    /// "Yeni mesaj": the capsule that leads down to a message that came while the user read further up (H2).
    package let newMessageLabel: String
}

package struct Announcement: Sendable, Equatable {
    package let id: String
    package let text: String
}

/// White bar with the bottom hairline: back arrow, who is answering, ✕.
package struct ChatHeader: Sendable, Equatable {
    package enum Lead: Sendable, Equatable {
        /// Nobody has taken the conversation (the bot or a flow answers): the company's logo, its initial without
        /// one; never a person's face.
        case brand(ChatAvatar)
        /// The operator, 32 pt, with the green dot while online.
        case person(ChatAvatar, online: Bool)
    }

    package let lead: Lead
    /// The brand, or the operator's name.
    package let title: String
    /// header_subtitle (the reply time unless the panel wrote its own), the reply time while queued, the company
    /// under an operator ("Example"), or that it is after hours.
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
        /// A voice message (CM-130): drawn by VoiceMessageBubble, in the strings' words.
        case voice(VoiceNote, ClomniStrings)
        case form(FormCard)
        case rating(RatingCard)
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
        /// The clock while it goes, then ✓ (in the brand colour once read).
        package enum Mark: Sendable, Equatable { case sending, sent, read }

        /// "Göndərilir", "Göndərildi", "Oxundu": only VoiceOver reads it, the screen shows `mark`. A failure,
        /// "Göndərilmədi · Yenidən cəhd et", is on screen in words.
        package let text: String
        package let isFailure: Bool
        /// The client id to send again when the failure is tapped.
        package let retryId: String?
        /// After the bubble's time, in the bubble; nil for a failure.
        package let mark: Mark?

        package init(text: String, isFailure: Bool, retryId: String?, mark: Mark? = nil) {
            self.text = text
            self.isFailure = isFailure
            self.retryId = retryId
            self.mark = mark
        }
    }

    package let id: String
    package let side: Side
    package let body: Body
    package let position: Position
    /// Next to the last bubble of an incoming run.
    package let avatar: ChatAvatar?
    /// Over the first bubble of an incoming run, outside it: who, the brand for the bot ("Clomni"), "Leyla"
    /// (DESIGN-PASS-3 B2).
    package let nameLine: String?
    /// In the bubble's bottom-trailing corner, every bubble's (operator, 2026-10-07, G7): "12:42".
    package let time: String
    /// On every message of the user's: its mark after the time, or a failure in words under the bubble.
    package let status: Status?
    /// The message, who sent it and when, and its status unless that is a failure (which is a button of its own):
    /// "Siz, 10:30: Salam. Oxundu". VoiceOver reads the bubble, its meta line and its status as one element.
    package let accessibilityLabel: String
    /// What a tap does, where it is not plain: "Şəkli tam ekranda açır", "Faylı açır".
    package let accessibilityHint: String?
    /// The message this one answers, in a small block at the top of the bubble; a tap scrolls to it.
    package let quote: Quote?
    /// The server's id; nil while the message is still on its way.
    package let messageId: String?
    /// A swipe to the right or "Cavabla" quotes it in the composer: only while there is a composer to write in.
    package let replyable: Bool
    /// What "Kopyala" copies: the text or the caption; nil when there is nothing to copy.
    package let copyText: String?

    /// Who wrote the quoted message ("Siz", "Leyla", the brand) and one line of it, or "Mesaj silinib".
    package struct Quote: Sendable, Equatable {
        package let messageId: String
        package let author: String
        package let excerpt: String
    }
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
        /// On screen: the label, with "(istəyə görə)" after an optional field's; a required one has no mark.
        package let shownLabel: String
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

/// A rating (CSAT) in a bot bubble: the question, then five faces or five stars. A choice sends at once, or opens a
/// comment field and "Göndər" when the panel asks for a comment. Sent, the choice stays lit with the thanks under it.
package struct RatingCard: Sendable, Equatable {
    package struct Option: Sendable, Equatable, Identifiable {
        package let score: Int
        /// 😞 😑 😐 😀 😍 for `emoji_5`; nil for a star.
        package let face: String?
        /// "Əla", "5 ulduzdan 4".
        package let accessibilityLabel: String

        package var id: Int { score }
    }

    package enum State: Sendable, Equatable {
        case open
        /// Sent or on its way: nothing changes it. `score` is nil when the rating is closed without one the SDK knows
        /// (the server took another answer, or no longer takes any): no choice lit, no thanks.
        case sent(score: Int?, comment: String?)
    }

    package let messageId: String
    package let text: [TextRun]
    package let options: [Option]
    /// The comment's field, a textarea like a form's; nil when the rating takes no comment.
    package let commentField: FormCard.Field?
    package let state: State
    package let submitTitle: String
    /// Under a sent rating: "Rəyiniz üçün təşəkkür edirik".
    package let thanks: String
    /// What VoiceOver reads for a sent rating: "Qiymətiniz: Əla. Rəyiniz üçün təşəkkür edirik".
    package let sentAccessibilityLabel: String?
}

package struct ChatComposer: Sendable, Equatable {
    package enum Mode: Sendable, Equatable {
        case open
        /// A step waits for a choice: no composer at all, no "choose above" (DESIGN-PASS-3 A4).
        case hidden
        /// "Söhbət bağlanıb · Yeni söhbət başlat"; writing anyway reopens it.
        case closed(text: String, action: String)
    }

    package let mode: Mode
    package let placeholder: String
    package let showsAttach: Bool
    /// Characters a message may have.
    package let limit: Int
    package let sendLabel: String
    package let attachLabel: String
    /// The attachment sheet's rows: the photo library, the camera, any file; and the x on a picked file.
    package let mediaLabel: String
    package let cameraLabel: String
    package let fileLabel: String
    package let removeAttachmentLabel: String
    /// The message being answered, over the field with its ✕ (`cancelQuoteLabel`).
    package let quote: Bubble.Quote?
    package let cancelQuoteLabel: String
    /// The longest voice message (config limits.voice_seconds): the recorder stops there.
    package var voiceSeconds = MessengerConfig.Limits.defaultVoiceSeconds
    /// The recorder's and the round button's texts (CM-130).
    package var texts = ClomniStrings(language: nil)
}

extension ChatSnapshot {
    /// A flow waits for a choice and the last message offers it: nobody is writing, whatever the last "typing" said
    /// (operator, 2026-10-06).
    package var awaitsChoice: Bool {
        guard let flow = conversation?.flow, flow.active, flow.awaiting != nil, pending.isEmpty,
              let last = messages.last(where: { if case .system = $0.content { return false }; return true }),
              case .quickReplies = last.content else { return false }
        return answerable.contains(last.id)
    }
}

extension ChatSnapshot {
    /// The flow holds the composer for a choice or a form, yet nothing on screen answers it: its choices were taken
    /// and no step came after (a choice that leads nowhere, "next": null, CM-087), and nothing is on its way.
    package var waitsForNothingShown: Bool {
        guard let flow = conversation?.flow, flow.holdsTheComposer, flow.awaiting == "menu" || flow.awaiting == "form",
              pending.isEmpty, ChatPresenter.liveChoices(self) == nil else { return false }
        return !messages.contains { message in
            if case .form(let form) = message.content { return form.submitted == nil && answerable.contains(message.id) }
            return false
        }
    }
}

extension Sender {
    /// This sender is the one shown `typing`: the same kind, and the same person when both are named; a bot is a bot.
    package func isTyping(_ typing: Sender) -> Bool {
        type == typing.type && (type == .bot || id == nil || typing.id == nil || id == typing.id)
    }
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
    /// The message the user is answering (swipe or "Cavabla"), until it is sent or dismissed.
    package var replyingTo: String?
    /// The flow says it waits for a choice or a form that is not there to answer (`waitsForNothingShown`), and has
    /// for a while: the composer is back, so the user is not stuck.
    package var flowStalled = false

    package init(config: MessengerConfig? = nil, conversation: Conversation? = nil, messages: [Message] = []) {
        self.config = config
        self.conversation = conversation
        self.messages = messages
    }
}
