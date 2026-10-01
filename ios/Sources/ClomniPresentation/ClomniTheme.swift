import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// The design tokens of brief 8 · 7.1, the same names on every platform. One accent colour comes from the config;
/// everything else is neutral grey.
public struct ClomniTheme: Sendable, Equatable {
    public struct Colors: Sendable, Equatable {
        /// User messages, pill text, send, active icons. One step lighter in dark mode.
        public let primary: RGBColor
        /// The top of the Home header's gradient: one step darker than `primary`.
        public let primaryDark: RGBColor
        /// Pill borders: `primary` at 25% over the background; a muted dark tone of the brand hue in dark mode.
        public let primarySoft: RGBColor
        /// Text on `primary`: the config's colour, or white or black, whichever reaches 4.5:1.
        public let onPrimary: RGBColor
        public let background: RGBColor
        /// Behind the Home cards.
        public let canvas: RGBColor
        /// Bot and operator messages, the composer field.
        public let surface: RGBColor
        public let textPrimary: RGBColor
        public let textSecondary: RGBColor
        public let border: RGBColor
        public let unread: RGBColor
        /// The operator's online dot in the conversation header.
        public let online: RGBColor
        /// The thin yellow "no internet" strip (brief 8 · 7.5) and its text.
        public let warning: RGBColor
        public let onWarning: RGBColor
    }

    public let colors: Colors
    public let isDark: Bool

    /// pt (iOS) = dp (Android).
    public enum Radius {
        public static let message: Double = 16
        /// The corner where messages of one group meet.
        public static let messageJoined: Double = 5
        public static let pill: Double = 18
        public static let card: Double = 12
        public static let input: Double = 20
        public static let logo: Double = 6
        public static let channel: Double = 8
    }

    /// Font sizes in pt; text scales with Dynamic Type from these.
    public enum FontSize {
        public static let greeting: Double = 22
        public static let brand: Double = 17
        public static let title: Double = 14.5
        public static let text: Double = 14
        public static let preview: Double = 13
        public static let secondary: Double = 12.5
        public static let label: Double = 12
        public static let meta: Double = 11
    }

    public enum Space {
        public static let xxs: Double = 3
        public static let xs: Double = 6
        public static let s: Double = 8
        public static let m: Double = 10
        public static let l: Double = 12
        public static let xl: Double = 14
        public static let xxl: Double = 18
    }

    public enum Size {
        public static let logo: Double = 22
        public static let headerAvatar: Double = 24
        /// Header avatars overlap by this much.
        public static let headerAvatarOverlap: Double = 7
        public static let avatar: Double = 28
        public static let channel: Double = 30
        public static let unreadDot: Double = 7
        public static let tabDot: Double = 8
        public static let tabIcon: Double = 22
        /// The cards ride up over the header by this much.
        public static let cardOverlap: Double = 40
        /// No tap target is smaller, whatever it looks like.
        public static let touchTarget: Double = 44
    }

    /// shadow.card: two soft layers in light mode; dark mode draws a 1 pt border instead.
    public struct Shadow: Sendable, Equatable {
        public let opacity: Double
        public let radius: Double
        public let y: Double

        public static let card = [Shadow(opacity: 0.06, radius: 2, y: 1), Shadow(opacity: 0.05, radius: 10, y: 2)]
    }

    /// Clomni's own colour, for a config that has none.
    public static let defaultPrimary = RGBColor(hex: MessengerConfig.Brand.defaultPrimaryColor) ?? .black

    public static func make(brand: MessengerConfig.Brand?, dark: Bool) -> ClomniTheme {
        let base = brand.flatMap { RGBColor(hex: $0.primaryColor) } ?? defaultPrimary
        let primary = dark ? base.steps(1) : base
        let background = dark ? hex("#121316") : .white
        let (hue, saturation, _) = base.hsl
        let colors = Colors(
            primary: primary,
            primaryDark: primary.steps(-1),
            primarySoft: dark ? RGBColor(hue: hue, saturation: saturation / 2, lightness: 0.28)
                : primary.over(background, opacity: 0.25),
            onPrimary: brand?.onPrimaryColor.flatMap { RGBColor(hex: $0) } ?? readableText(on: primary),
            background: background,
            canvas: hex(dark ? "#0B0C0E" : "#F5F6F8"),
            surface: hex(dark ? "#22242A" : "#F1F2F4"),
            textPrimary: hex(dark ? "#F2F3F5" : "#1B1D21"),
            // #707480 rather than the brief's #737780, which is 4.49:1 on white (decided in CM-082).
            textSecondary: hex(dark ? "#9A9DA6" : "#707480"),
            border: hex(dark ? "#2A2C32" : "#E7E8EB"),
            unread: hex("#E5484D"),
            online: hex("#30C26B"),
            warning: hex(dark ? "#3D3415" : "#FFF4CC"),
            onWarning: hex(dark ? "#F2DC8B" : "#5C4400"))
        return ClomniTheme(colors: colors, isDark: dark)
    }

    private static func hex(_ value: String) -> RGBColor {
        RGBColor(hex: value) ?? .black
    }

    /// The config's `brand.theme` wins over the system's appearance unless it says `system`.
    public static func isDark(_ theme: MessengerConfig.Theme?, systemIsDark: Bool) -> Bool {
        switch theme {
        case .dark?: return true
        case .light?: return false
        default: return systemIsDark
        }
    }

    /// White when it reaches 4.5:1 (WCAG AA for body text) on `background`, otherwise black, which then always does:
    /// one of the two reaches at least 4.58:1 on any colour.
    public static func readableText(on background: RGBColor) -> RGBColor {
        background.contrast(with: .white) >= 4.5 ? .white : .black
    }
}
