import Foundation

/// One circle of "Bizi izləyin" (DESIGN-PASS-3 D2): the platform's monochrome mark, or an SF Symbol for email, phone
/// and a website, all in the text colour; and its name for VoiceOver.
package struct ChannelItem: Sendable, Equatable, Identifiable {
    package enum Glyph: Sendable, Equatable {
        /// A brand mark in a 24×24 box (see `BrandMarks`).
        case brand(SVGPath)
        case symbol(String)
    }

    package let id: String
    package let url: URL
    package let glyph: Glyph
    package let accessibilityLabel: String

    init(type: String, url: URL, strings: ClomniStrings) {
        id = "\(type) \(url.absoluteString)"
        self.url = url
        if url.scheme == "mailto" || type.lowercased() == "email" {
            glyph = .symbol("envelope")
            accessibilityLabel = strings[.email]
        } else if url.scheme == "tel" || type.lowercased() == "phone" {
            glyph = .symbol("phone")
            accessibilityLabel = strings[.phone]
        } else if let mark = BrandMarks.mark(for: type.lowercased()) {
            glyph = .brand(mark.path)
            accessibilityLabel = mark.name
        } else {
            glyph = .symbol("globe")
            accessibilityLabel = url.host ?? url.absoluteString
        }
    }
}
