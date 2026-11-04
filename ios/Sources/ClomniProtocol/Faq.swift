import Foundation

/// GET /v1/faq (protocol/schema/faq.json, SDK 1.0.7): a published question and its answer, in the panel's order and in
/// one language.
package struct FaqItem: Sendable, Equatable, Identifiable {
    /// "faq_12".
    package let id: String
    package let question: String
    /// The news item's light markdown: **bold**, *italic*, [links](…), - lists and line breaks.
    package let answer: String
    package let updatedAt: Date?

    package init(id: String, question: String, answer: String, updatedAt: Date? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.updatedAt = updatedAt
    }
}

extension FaqItem {
    /// Read leniently, like the news: a question without an id, its text or an answer is left out.
    init(_ f: JSONFields) throws {
        let question = try f.string("question")
        let answer = try f.string("answer")
        guard !question.isEmpty, !answer.isEmpty else { throw ParseError("\(f.path): an empty question or answer") }
        self.init(id: try f.string("id"), question: question, answer: answer,
                  updatedAt: f.optionalString("updated_at").flatMap(ISOTime.parse))
    }
}
