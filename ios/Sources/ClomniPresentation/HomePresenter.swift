import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// Everything the Home tab shows, decided here so the SwiftUI view only draws it (brief 8 · 7.3, 7.5).
package struct HomeScreen: Sendable, Equatable {
    package enum Phase: Sendable, Equatable {
        /// Nothing cached yet: grey skeleton blocks, no spinner.
        case loading
        case ready
        /// Nothing cached and the server failed: "Nəsə səhv getdi" + "Yenidən cəhd et".
        case failed
    }

    package struct Header: Sendable, Equatable {
        package let brandName: String
        package let logoUrl: URL?
        /// In dark mode instead of `logoUrl`, when the panel has one.
        package let logoDarkUrl: URL?
        package let style: Style
        /// A soft glow of the brand colour behind the header.
        package let glow: Bool
        /// Stands in for the logo while there is none.
        package let brandInitial: String
        /// The full logo in place of the logo (APPEARANCE-CONTRACT § 4a); nil: the logo.
        package let wordmark: Wordmark?
        /// The logo's (or the full logo's) height: 32 at 100%, times the panel's `brand.logo_scale`.
        package let logoHeight: Double
        /// Up to three, overlapping.
        package let teamAvatars: [URL]
        /// "Salam, Aysel".
        package let greeting: String
        /// "Necə kömək edə bilərik?"
        package let title: String
        /// The panel's size for the two lines.
        package let titleSize: TitleSize
        package let closeLabel: String
    }

    package struct Wordmark: Sendable, Equatable {
        package let url: URL
        /// In dark mode instead of `url`, when the panel has one.
        package let darkUrl: URL?
    }

    /// The greeting's two lines (DESIGN-PASS-2 3): both 28 at 100%, times the panel's `home.title_scale`; each line
    /// 1.2 times its size apart. Dynamic Type scales them further.
    package struct TitleSize: Sendable, Equatable {
        package static let base: Double = 28
        package static let lineHeight = 1.2

        package let greeting: Double
        package let title: Double

        /// `scale`: percent, 70 to 140.
        package init(scale: Int) {
            let size = Self.base * Double(min(140, max(70, scale))) / 100
            (greeting, title) = (size, size)
        }

    }

    /// The header's background: the brand gradient (header_from → header_to), one colour, or a picture under a dark
    /// veil (black 35% → 55%) with white text.
    package enum Style: Sendable, Equatable {
        case gradient, solid
        case image(URL)
    }

    /// "Bizə mesaj göndərin" with the reply time under it.
    package struct NewConversationCard: Sendable, Equatable {
        package let title: String
        package let subtitle: String?
        package let accessibilityLabel: String
    }

    package struct RecentCard: Sendable, Equatable {
        package let label: String
        package let row: ConversationRow
    }

    package struct ChannelsCard: Sendable, Equatable {
        /// Five 44 pt circles with their 12 pt gaps need 268 pt, 4 more than the card has on the narrowest iPhone
        /// (264): fixed rows (iOS 15) hold four, the fifth under them.
        package static let iconsPerRow = 4

        package let label: String
        package let items: [ChannelItem]

        /// The icons in rows that never run past the card (fixed rows where the layout cannot wrap by itself).
        package func rows(of size: Int = iconsPerRow) -> [[ChannelItem]] {
            let size = max(1, size)
            return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
        }
    }

    /// The first three published news, in the panel's order.
    package struct NewsCard: Sendable, Equatable {
        package struct Item: Sendable, Equatable, Identifiable {
            package let id: String
            package let title: String
            package let summary: String?
            /// The cover, 16:9 at the top of the card.
            package let imageUrl: URL?
            package let accessibilityLabel: String
        }

        package static let maxItems = 3
        package let items: [Item]
    }

    /// "Mesajlar" with its icon: the way to the conversations, always on Home (there is no tab bar).
    package struct MessagesCard: Sendable, Equatable {
        package let title: String
        /// The red dot next to the icon.
        package let unread: Bool
        package let accessibilityLabel: String
    }

    package struct Failure: Sendable, Equatable {
        package let message: String
        package let retry: String
    }

    package let phase: Phase
    package let header: Header
    /// nil hides a card.
    package let newConversation: NewConversationCard?
    package let recent: RecentCard?
    package let channels: ChannelsCard?
    package let messagesCard: MessagesCard
    package let news: NewsCard?
    /// The capsule over the screen while offline (CM-077).
    package let offline: String?
    /// "Qoşuldu": the capsule's word for a second once the connection is back.
    package let connected: String
    package let failure: Failure?
    /// What VoiceOver reads over the skeleton: "Yüklənir".
    package let loadingLabel: String
    /// The cards there are, in the panel's order.
    package let order: [MessengerConfig.HomeCard]
    /// "Powered by" under the cards, with Clomni's wordmark after it (DESIGN-PASS-3 H3), unless the plan turned it off.
    package let poweredBy: String?
}

/// A conversation in a list, and the "Son mesaj" card.
package struct ConversationRow: Sendable, Equatable, Identifiable {
    package let id: String
    package let avatarUrl: URL?
    /// Shown while the avatar loads, or when there is none.
    package let initial: String
    /// The last message, one line.
    package let preview: String
    /// "Leyla · 2 dəq"
    package let detail: String
    package let unread: Bool
    package let accessibilityLabel: String
}

/// The Messages tab.
package struct MessagesScreen: Sendable, Equatable {
    package let title: String
    package let phase: HomeScreen.Phase
    package let rows: [ConversationRow]
    /// "Hələ söhbət yoxdur", when the list is loaded and empty.
    package let empty: String?
    package let newConversation: HomeScreen.NewConversationCard
    package let offline: String?
    package let connected: String
    package let failure: HomeScreen.Failure?
    package let loadingLabel: String
    /// VoiceOver's name for the back button.
    package let backLabel: String
}

/// What the screens are built from.
package struct MessengerSnapshot: Sendable, Equatable {
    package enum Load: Sendable, Equatable { case loading, loaded, failed }

    package var config: MessengerConfig?
    package var configLoad = Load.loading
    /// Newest first.
    package var conversations: [Conversation] = []
    package var conversationsLoad = Load.loading
    package var unreadTotal = 0
    /// The published news (GET /news), the first three on Home.
    package var news: [NewsItem] = []
    /// The logged-in user's name, for the greeting.
    package var userName: String?
    package var isOffline = false

    package init(config: MessengerConfig? = nil, conversations: [Conversation] = [], userName: String? = nil) {
        self.config = config
        self.conversations = conversations
        self.userName = userName
    }
}

package struct HomePresenter: Sendable {
    package let strings: ClomniStrings
    private let time: TimeText
    private let now: Date

    package init(strings: ClomniStrings, timeZone: TimeZone = .current, now: Date) {
        self.strings = strings
        time = TimeText(strings: strings, timeZone: timeZone)
        self.now = now
    }

    package func home(_ snapshot: MessengerSnapshot) -> HomeScreen {
        let config = snapshot.config
        let cards = config?.home.cards ?? MessengerConfig.HomeCard.allCases
        let recent = cards.contains(.recent) ? snapshot.conversations.lazy
            .compactMap { row($0, config: config) }.first.map { HomeScreen.RecentCard(label: strings[.recentMessage], row: $0) }
            : nil
        let items = (config?.home.channels ?? []).map { ChannelItem(type: $0.type, url: $0.url, strings: strings) }
        let channels = cards.contains(.channels) && !items.isEmpty
            ? HomeScreen.ChannelsCard(label: strings[.followUs], items: items) : nil
        let failed = config == nil && snapshot.configLoad == .failed
        let newsItems = snapshot.news.prefix(HomeScreen.NewsCard.maxItems).map {
            HomeScreen.NewsCard.Item(id: $0.id, title: $0.title, summary: $0.summary, imageUrl: $0.imageUrl,
                                     accessibilityLabel: [$0.title, $0.summary].compactMap { $0 }.joined(separator: ". "))
        }
        let news = cards.contains(.news) && !newsItems.isEmpty ? HomeScreen.NewsCard(items: newsItems) : nil
        return HomeScreen(
            phase: config != nil ? .ready : failed ? .failed : .loading,
            header: header(snapshot),
            newConversation: newConversation(config),
            recent: recent,
            channels: channels,
            messagesCard: messagesCard(snapshot),
            news: news,
            offline: snapshot.isOffline ? strings[.offline] : nil,
            connected: strings[.connected],
            failure: failed ? failure : nil,
            loadingLabel: strings[.loading],
            order: cards.filter { card in
                switch card {
                case .messages, .send: return true
                case .recent: return recent != nil
                case .channels: return channels != nil
                case .news: return news != nil
                }
            },
            poweredBy: config?.poweredBy == false ? nil : "Powered by")
    }

    /// The open messenger before the SDK is ready: skeletons, or "Nəsə səhv getdi" with "Yenidən cəhd et" when
    /// getting ready failed.
    package func preparing(failed: Bool) -> HomeScreen {
        var snapshot = MessengerSnapshot()
        snapshot.configLoad = failed ? .failed : .loading
        return home(snapshot)
    }

    package func messages(_ snapshot: MessengerSnapshot) -> MessagesScreen {
        let rows = snapshot.conversations.compactMap { row($0, config: snapshot.config) }
        let failed = rows.isEmpty && snapshot.conversationsLoad == .failed
        let phase: HomeScreen.Phase = !rows.isEmpty || snapshot.conversationsLoad == .loaded ? .ready
            : failed ? .failed : .loading
        return MessagesScreen(
            title: strings[.messagesTitle], phase: phase, rows: rows,
            empty: phase == .ready && rows.isEmpty ? strings[.emptyList] : nil,
            newConversation: newConversation(snapshot.config),
            offline: snapshot.isOffline ? strings[.offline] : nil,
            connected: strings[.connected],
            failure: failed ? failure : nil,
            loadingLabel: strings[.loading],
            backLabel: strings[.goBack])
    }

    /// A conversation with a last message; one without has nothing to show yet.
    package func row(_ conversation: Conversation, config: MessengerConfig?) -> ConversationRow? {
        guard let message = conversation.lastMessage else { return nil }
        let botName = config?.bot.name.isEmpty == false ? config?.bot.name : nil
        let name: String
        switch message.sender.type {
        case .user: name = strings[.you]
        case .bot: name = message.sender.name ?? botName ?? config?.brand.name ?? ""
        case .operator: name = message.sender.name ?? conversation.assignee?.name ?? config?.brand.name ?? ""
        case .system, .unknown: name = config?.brand.name ?? ""
        }
        // The avatar is the other side's: the operator's own picture, or the bot's as in the conversation (the
        // panel's bot picture first, then the brand's logo, then the initial).
        let other: (name: String, avatar: URL?)
        switch message.sender.type {
        case .user, .system:
            other = (conversation.assignee?.name ?? botName ?? config?.brand.name ?? "",
                     conversation.assignee?.avatarUrl ?? config?.botAvatarUrl)
        case .bot:
            other = (name, config?.bot.avatarUrl ?? message.sender.avatarUrl ?? config?.brand.logoUrl)
        case .operator, .unknown:
            other = (name, message.sender.avatarUrl)
        }
        let preview = Self.plainText(message)
        let ago = time.ago(message.createdAt, now: now)
        let unread = conversation.unreadCount > 0
        return ConversationRow(
            id: conversation.id, avatarUrl: other.avatar,
            initial: other.name.first.map { String($0).uppercased() } ?? "",
            preview: preview, detail: "\(name) · \(ago)", unread: unread,
            accessibilityLabel: "\(name), \(ago): \(preview)" + (unread ? ". \(strings[.unread])" : ""))
    }

    private func header(_ snapshot: MessengerSnapshot) -> HomeScreen.Header {
        let config = snapshot.config
        let brand = config?.brand.name ?? ""
        let style: HomeScreen.Style
        switch config?.brand.headerStyle {
        case .solid?: style = .solid
        case .image?: style = config?.brand.headerImageUrl.map(HomeScreen.Style.image) ?? .gradient
        default: style = .gradient
        }
        return HomeScreen.Header(
            brandName: brand, logoUrl: config?.brand.logoUrl, logoDarkUrl: config?.brand.logoDarkUrl, style: style,
            glow: config?.brand.glow ?? false,
            brandInitial: brand.first.map { String($0).uppercased() } ?? "",
            wordmark: config.flatMap { config in
                guard config.brand.logoStyle == .wordmark, let url = config.brand.wordmarkUrl else { return nil }
                return HomeScreen.Wordmark(url: url, darkUrl: config.brand.wordmarkDarkUrl)
            },
            logoHeight: ClomniTheme.Size.logo * Double(config?.brand.logoScale ?? 100) / 100,
            teamAvatars: config?.team.show == false ? [] : Array((config?.team.avatars ?? []).prefix(3)),
            greeting: greeting(snapshot.userName),
            title: strings[.greetingLine2],
            titleSize: HomeScreen.TitleSize(scale: config?.home.titleScale ?? 100),
            closeLabel: strings[.close])
    }

    /// greeting_line1 with {name} and {first_name} filled in from the user's name; greeting_line1_anonymous without
    /// one.
    package func greeting(_ userName: String?) -> String {
        let name = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let firstName = name.split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            return strings[.greetingLine1Anonymous]
        }
        return strings[.greetingLine1].replacingOccurrences(of: "{first_name}", with: firstName)
            .replacingOccurrences(of: "{name}", with: name)
    }

    private func newConversation(_ config: MessengerConfig?) -> HomeScreen.NewConversationCard {
        let title = strings[.sendCardTitle]
        let closed = config?.team.officeHours?.openNow == false
        let subtitle = closed ? config?.team.replyTimeOffline ?? config?.team.replyTime : config?.team.replyTime
        return HomeScreen.NewConversationCard(title: title, subtitle: subtitle,
                                              accessibilityLabel: subtitle.map { "\(title). \($0)" } ?? title)
    }

    private func messagesCard(_ snapshot: MessengerSnapshot) -> HomeScreen.MessagesCard {
        let unread = snapshot.unreadTotal > 0 || snapshot.conversations.contains { $0.unreadCount > 0 }
        let messages = strings[.messagesTitle]
        let label = unread ? "\(messages), \(strings[.unreadMessages])" : messages
        return HomeScreen.MessagesCard(title: messages, unread: unread, accessibilityLabel: label)
    }

    private var failure: HomeScreen.Failure {
        HomeScreen.Failure(message: strings[.error], retry: strings[.retry])
    }

    /// One line of a message: its text without the markdown marks, or the fallback text of other types.
    static func plainText(_ message: Message) -> String {
        guard case .text(var text) = message.content else { return oneLine(message.fallbackText) }
        // [label](url) → label, then the bold and italic marks.
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: #"(^|[^\w*])\*([^*\n]+)\*"#, with: "$1$2", options: .regularExpression)
        return oneLine(text)
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension MessengerConfig {
    /// The bot's picture: its own, else the brand's logo; nil leaves its initial.
    package var botAvatarUrl: URL? {
        bot.avatarUrl ?? brand.logoUrl
    }
}

/// A news item's screen (DESIGN-PASS-2 "Xəbərlər"): the cover, the title 24 bold, the date 13, the text with its
/// markdown, and the button.
package struct NewsArticle: Sendable, Equatable {
    package let id: String
    package let imageUrl: URL?
    package let title: String
    /// "2 okt", or with the year when it is not this one.
    package let date: String
    /// Paragraphs; a "- " line is a list item.
    package let blocks: [Block]
    package let button: NewsItem.Button?
    package let backLabel: String
    package let closeLabel: String

    package enum Block: Sendable, Equatable {
        case paragraph([TextRun])
        case listItem([TextRun])
    }

    package init(_ item: NewsItem, strings: ClomniStrings, time: TimeText, now: Date) {
        id = item.id
        imageUrl = item.imageUrl
        title = item.title
        date = time.day(item.publishedAt, now: now)
        blocks = (item.bodyMarkdown ?? "").components(separatedBy: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            if text.hasPrefix("- ") { return .listItem(LimitedMarkdown.parse(String(text.dropFirst(2)))) }
            return .paragraph(LimitedMarkdown.parse(text))
        }
        button = item.button
        backLabel = strings[.goBack]
        closeLabel = strings[.close]
    }
}

/// What the offline capsule says (CM-077), the same on every screen: nothing, "İnternet yoxdur", or "Qoşuldu" for
/// `backSeconds` once the connection is back.
package enum OfflineNotice: Sendable, Equatable {
    case hidden, offline, back

    package static let backSeconds = 1.0

    /// Where it goes when the network becomes `offline`: only coming back from offline says "Qoşuldu".
    package func next(offline: Bool) -> OfflineNotice {
        if offline { return .offline }
        return self == .offline ? .back : self
    }

    /// "Qoşuldu" has had its second.
    package func expired() -> OfflineNotice {
        self == .back ? .hidden : self
    }
}
