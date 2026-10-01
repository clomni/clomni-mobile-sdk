import Foundation

/// One icon of "Bizi izləyin". Brand logos are not drawn: each platform gets its colour and a plain SF Symbol, and its
/// name for VoiceOver.
public struct ChannelItem: Sendable, Equatable, Identifiable {
    public enum Tint: Sendable, Equatable {
        /// The platform's colour behind a white symbol.
        case brand(RGBColor)
        /// The theme's surface behind a symbol in the text colour (email, phone, links).
        case neutral
    }

    public let id: String
    public let url: URL
    /// SF Symbol name.
    public let symbol: String
    public let tint: Tint
    public let accessibilityLabel: String

    init(type: String, url: URL, strings: ClomniStrings) {
        let kind = url.scheme == "mailto" ? "email" : url.scheme == "tel" ? "phone" : type.lowercased()
        let style = Self.styles[kind]
        id = "\(type) \(url.absoluteString)"
        self.url = url
        symbol = style?.symbol ?? "link"
        tint = style?.color.flatMap { RGBColor(hex: $0) }.map(Tint.brand) ?? .neutral
        switch kind {
        case "email": accessibilityLabel = strings[.email]
        case "phone": accessibilityLabel = strings[.phone]
        default: accessibilityLabel = style?.name ?? url.host ?? url.absoluteString
        }
    }

    private static let styles: [String: (name: String, symbol: String, color: String?)] = [
        "instagram": ("Instagram", "camera", "#E4405F"),
        "whatsapp": ("WhatsApp", "phone.fill", "#25D366"),
        "telegram": ("Telegram", "paperplane.fill", "#229ED9"),
        "facebook": ("Facebook", "hand.thumbsup.fill", "#1877F2"),
        "messenger": ("Messenger", "bubble.left.fill", "#0084FF"),
        "linkedin": ("LinkedIn", "briefcase.fill", "#0A66C2"),
        "youtube": ("YouTube", "play.fill", "#FF0000"),
        "tiktok": ("TikTok", "music.note", "#EE1D52"),
        // X's colour is black, which would vanish in dark mode.
        "x": ("X", "at", nil),
        "twitter": ("X", "at", nil),
        "email": ("", "envelope", nil),
        "phone": ("", "phone", nil),
    ]
}
