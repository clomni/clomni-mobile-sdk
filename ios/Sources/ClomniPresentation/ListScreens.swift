import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// The tabs under the messenger's list screens (config home.tab_bar, SDK 1.0.7): Home, the conversations with the
/// unread count, the news while there are some, the FAQ while it is on and has a question. A conversation, a news
/// item and anything else pushed over a list has none.
package struct TabBar: Sendable, Equatable {
    package enum Tab: String, Sendable, Equatable, CaseIterable {
        case home, messages, news, faq
    }

    package struct Item: Sendable, Equatable, Identifiable {
        package let tab: Tab
        package let title: String
        /// The unread count on the conversations' tab: "3", "99+"; nil when nothing is unread.
        package let badge: String?
        package let accessibilityLabel: String

        package var id: Tab { tab }
    }

    package let items: [Item]

    package func contains(_ tab: Tab) -> Bool {
        items.contains { $0.tab == tab }
    }

    static func badge(_ count: Int) -> String? {
        count > 0 ? (count > 99 ? "99+" : String(count)) : nil
    }
}

/// Every published news item, from Home's "Hamısı" or the news tab; a tap opens the item.
package struct NewsListScreen: Sendable, Equatable {
    /// "Xəbərlər"
    package let title: String
    package let items: [HomeScreen.NewsCard.Item]
    package let backLabel: String
    package let closeLabel: String
    package let tabBar: TabBar?

    /// The items as Home's news card draws them, all of them and no "Hamısı".
    package var card: HomeScreen.NewsCard { HomeScreen.NewsCard(items: items, seeAll: nil) }
}

/// The FAQ (SDK 1.0.7): "Tez-tez verilən suallar", the search field, the questions in the panel's order; a question
/// opens its answer on a screen of its own, drawn as a news item.
package struct FaqScreen: Sendable, Equatable {
    package struct Entry: Sendable, Equatable, Identifiable {
        package let id: String
        package let question: String
        /// The question and the answer without its marks, for the search.
        let searchable: String

        package init(_ item: FaqItem) {
            id = item.id
            question = item.question
            searchable = FaqScreen.folded(item.question + "\n" + LimitedMarkdown.plainText(item.answer))
        }
    }

    package let title: String
    /// "Sual axtarın"
    package let searchPlaceholder: String
    /// "Hələ sual yoxdur": no questions at all.
    package let empty: String
    /// "Heç nə tapılmadı": the search found none.
    package let noResults: String
    package let entries: [Entry]
    package let backLabel: String
    package let closeLabel: String
    package let tabBar: TabBar?

    /// The questions whose text or answer has every word of `query`, ignoring case and marks ("ödəniş" finds
    /// "Ödənişi"); all of them for an empty query.
    package func matching(_ query: String) -> [Entry] {
        let words = Self.folded(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in words.allSatisfy { entry.searchable.contains($0) } }
    }

    /// Lower case, without diacritics; Azerbaijani's ı and ə read as i and e, so either spelling finds the other.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "az"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ə", with: "e")
    }
}
