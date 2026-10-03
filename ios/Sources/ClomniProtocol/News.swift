import Foundation

/// GET /v1/news (protocol/schema/news.json): the channel's published news in the panel's order, in one language.
package struct NewsItem: Sendable, Equatable, Identifiable {
    package struct Button: Sendable, Equatable {
        package let text: String
        /// https://… or the app's deep link; the app's `onLink` gets it, else the system opens it.
        package let url: URL

        package init(text: String, url: URL) {
            self.text = text
            self.url = url
        }
    }

    /// "news_12".
    package let id: String
    package let title: String
    /// Two lines on the card.
    package let summary: String?
    /// The item's screen: **bold**, *italic*, [links](…) and - lists.
    package let bodyMarkdown: String?
    /// The cover, drawn 16:9.
    package let imageUrl: URL?
    package let button: Button?
    package let publishedAt: Date
}

extension NewsItem {
    /// Read leniently: an item without an id, a title or a date is left out; a button without its text or link is
    /// no button.
    init(_ f: JSONFields) throws {
        id = try f.string("id")
        title = try f.string("title")
        summary = f.optionalString("summary").flatMap { $0.isEmpty ? nil : $0 }
        bodyMarkdown = f.optionalString("body_markdown").flatMap { $0.isEmpty ? nil : $0 }
        imageUrl = f.optionalURL("image_url")
        button = f.optionalObject("button").flatMap { button in
            guard let text = button.optionalString("text"), !text.isEmpty, let url = button.optionalURL("url"),
                  url.scheme != nil else { return nil }
            return Button(text: text, url: url)
        }
        publishedAt = try f.date("published_at")
    }
}
