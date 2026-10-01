import Foundation

/// One icon of "Bizi izləyin": the platform's own mark, white on its colour, so it is recognised at a glance; email,
/// phone and other links get an SF Symbol. Each has its name for VoiceOver.
public struct ChannelItem: Sendable, Equatable, Identifiable {
    public enum Glyph: Sendable, Equatable {
        /// A brand mark in a 24×24 box (see `BrandMarks`), drawn white on `color`.
        case brand(SVGPath, color: RGBColor)
        /// An SF Symbol in the text colour on the theme's surface.
        case symbol(String)
    }

    public let id: String
    public let url: URL
    public let glyph: Glyph
    public let accessibilityLabel: String

    init(type: String, url: URL, strings: ClomniStrings) {
        id = "\(type) \(url.absoluteString)"
        self.url = url
        if url.scheme == "mailto" || type.lowercased() == "email" {
            glyph = .symbol("envelope")
            accessibilityLabel = strings[.email]
        } else if url.scheme == "tel" || type.lowercased() == "phone" {
            glyph = .symbol("phone")
            accessibilityLabel = strings[.phone]
        } else if let mark = BrandMarks.mark(for: type.lowercased()), let color = RGBColor(hex: mark.color) {
            glyph = .brand(mark.path, color: color)
            accessibilityLabel = mark.name
        } else {
            glyph = .symbol("link")
            accessibilityLabel = url.host ?? url.absoluteString
        }
    }
}
