import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// The design tokens of brief 8 · 7.1, the same names on every platform. One accent colour comes from the config;
/// everything else is neutral grey.
package struct ClomniTheme: Sendable, Equatable {
    package struct Colors: Sendable, Equatable {
        /// User messages, pill text, send, active icons. One step lighter in dark mode.
        package let primary: RGBColor
        /// Text on `primary`: white, or black where white does not reach 4.5:1.
        package let onPrimary: RGBColor
        /// `primary` at 10% over the background: image placeholders and soft backgrounds.
        package let primarySoft: RGBColor
        /// `primary` at 22% over the background: pill borders.
        package let primaryLine: RGBColor
        /// The header, top to bottom: light to dark (one colour for a solid header).
        package let headerFrom: RGBColor
        package let headerTo: RGBColor
        /// Text and icons on the header: white where it reaches 3:1 on both header colours (the greeting is large
        /// text), else #1B1D21. Not `onPrimary`, which in dark mode can be black on a dark header.
        package let headerText: RGBColor
        /// The brand's strong tone, for Home's first greeting line (at 70%): two steps darker, in dark mode one
        /// lighter. The server's `primary_strong` once it sends one.
        package let primaryStrong: RGBColor
        package let background: RGBColor
        /// Behind the Home cards.
        package let canvas: RGBColor
        /// Bot and operator messages, the composer field.
        package let surface: RGBColor
        package let textPrimary: RGBColor
        package let textSecondary: RGBColor
        package let border: RGBColor
        package let unread: RGBColor
        /// The operator's online dot in the conversation header.
        package let online: RGBColor
        /// The thin yellow "no internet" strip (brief 8 · 7.5) and its text.
        package let warning: RGBColor
        package let onWarning: RGBColor
    }

    package let colors: Colors
    package let isDark: Bool

    /// pt (iOS) = dp (Android).
    package enum Radius {
        package static let message: Double = 16
        /// The corner where messages of one group meet.
        package static let messageJoined: Double = 5
        package static let pill: Double = 18
        package static let card: Double = 12
        /// Home's cards (DESIGN-PASS-2 5).
        package static let homeCard: Double = 16
        package static let input: Double = 20
        /// The Home header's logo (DESIGN-PASS 2).
        package static let logo: Double = 8
        package static let channel: Double = 8
    }

    /// Font sizes in pt; text scales with Dynamic Type from these.
    package enum FontSize {
        package static let greeting: Double = 22
        package static let brand: Double = 17
        package static let title: Double = 14.5
        package static let text: Double = 14
        package static let preview: Double = 13
        package static let secondary: Double = 12.5
        package static let label: Double = 12
        package static let meta: Double = 11
    }

    /// Multiples of 4 (DESIGN-PASS, the same on Android): 4 · 8 · 12 · 16 · 20 · 24 · 32.
    package enum Space {
        package static let xxs: Double = 4
        package static let xs: Double = 8
        package static let s: Double = 8
        package static let m: Double = 12
        package static let l: Double = 12
        package static let xl: Double = 16
        package static let xxl: Double = 20
        package static let xxxl: Double = 24
        /// Between the channel squares, so their 44 pt targets do not overlap.
        package static let channelGap: Double = 20
    }

    package enum Size {
        package static let logo: Double = 32
        /// The full logo's height on Home.
        package static let wordmark: Double = 32
        /// The close button on every screen (DESIGN-PASS-2 6): a 40 pt circle with a 20 pt ✕ drawn 2 pt thick, in a
        /// 44 pt target, 16 pt from the screen's side and 12 pt under the safe area.
        package static let closeCircle: Double = 40
        package static let closeGlyph: Double = 20
        package static let closeStroke: Double = 2
        /// Every screen's bar: its buttons this far from the side and under the safe area.
        package static let barEdge: Double = 16
        package static let barTop: Double = 12
        /// The conversation header's avatar.
        package static let headerLead: Double = 32
        package static let headerAvatar: Double = 24
        /// Header avatars overlap by this much.
        package static let headerAvatarOverlap: Double = 7
        package static let avatar: Double = 28
        package static let channel: Double = 30
        package static let unreadDot: Double = 7
        package static let tabDot: Double = 8
        /// Icons in Home's cards.
        package static let cardIcon: Double = 20
        /// No tap target is smaller, whatever it looks like.
        package static let touchTarget: Double = 44
    }

    /// shadow.card: one soft shadow in light mode (DESIGN-PASS: no stacked layers); dark mode draws a 1 pt border
    /// instead.
    package struct Shadow: Sendable, Equatable {
        package let opacity: Double
        package let radius: Double
        package let y: Double

        package static let card = Shadow(opacity: 0.06, radius: 3, y: 1)
    }

    /// Clomni's own colour, for a config that has none.
    package static let defaultPrimary = RGBColor(hex: MessengerConfig.Brand.defaultPrimaryColor) ?? .black

    /// The tokens for `brand`: the server's colours when it sent them, else derived here by the same rules
    /// (APPEARANCE-CONTRACT § 1). `primaryColor` (the app's `Clomni.setTheme`) wins over the panel: its tokens are
    /// always derived here.
    package static func make(brand: MessengerConfig.Brand?, dark: Bool, primaryColor: String? = nil) -> ClomniTheme {
        let background = dark ? hex("#121316") : .white
        var tokens: Tokens
        if let primaryColor, let base = RGBColor(hex: primaryColor) {
            tokens = derive(base, dark: dark)
        } else if let palette = dark ? brand?.colors?.dark : brand?.colors?.light {
            let from = hex(palette.headerFrom)
            let to = hex(palette.headerTo)
            tokens = Tokens(primary: hex(palette.primary), onPrimary: hex(palette.onPrimary),
                            primarySoft: hex(palette.primarySoft), primaryLine: hex(palette.primaryLine),
                            headerFrom: from, headerTo: to,
                            headerText: palette.headerText.flatMap { RGBColor(hex: $0) } ?? headerText(on: from, to))
        } else {
            tokens = derive(brand.flatMap { RGBColor(hex: $0.primaryColor) } ?? defaultPrimary, dark: dark)
        }
        if brand?.headerStyle == .solid, tokens.headerFrom != tokens.primary || tokens.headerTo != tokens.primary {
            tokens.headerFrom = tokens.primary
            tokens.headerTo = tokens.primary
            tokens.headerText = headerText(on: tokens.primary, tokens.primary)
        }
        if brand?.headerStyle == .image, brand?.headerImageUrl != nil {
            // Over the picture's dark veil.
            tokens.headerText = .white
        }
        let colors = Colors(
            primary: tokens.primary,
            onPrimary: tokens.onPrimary,
            primarySoft: tokens.primarySoft,
            primaryLine: tokens.primaryLine,
            headerFrom: tokens.headerFrom,
            headerTo: tokens.headerTo,
            headerText: tokens.headerText,
            primaryStrong: dark ? tokens.primary.steps(1) : tokens.primary.steps(-2),
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

    /// The theme the screens draw with: the config's, with the app's `Clomni.setTheme` over it. Without either (a
    /// first launch, before the config arrives) neutral grey: never a colour that is not the brand's.
    package static func make(config: MessengerConfig?, systemIsDark: Bool, override: ThemeOverride = ThemeOverride())
        -> ClomniTheme {
        let dark = isDark(override.mode ?? config?.theme.mode, systemIsDark: systemIsDark)
        if config == nil, override.primaryColor.flatMap(RGBColor.init(hex:)) == nil {
            return neutral(dark: dark)
        }
        return make(brand: config?.brand, dark: dark, primaryColor: override.primaryColor)
    }

    /// No brand yet: the header in the surface grey with dark text, the accent the secondary text grey.
    package static func neutral(dark: Bool) -> ClomniTheme {
        let base = make(brand: nil, dark: dark).colors
        let accent = base.textSecondary
        let header = base.surface
        let colors = Colors(
            primary: accent, onPrimary: readableText(on: accent),
            primarySoft: base.surface, primaryLine: base.border,
            headerFrom: header, headerTo: header, headerText: base.textPrimary, primaryStrong: base.textSecondary,
            background: base.background, canvas: base.canvas, surface: base.surface, textPrimary: base.textPrimary,
            textSecondary: base.textSecondary, border: base.border, unread: base.unread, online: base.online,
            warning: base.warning, onWarning: base.onWarning)
        return ClomniTheme(colors: colors, isDark: dark)
    }

    /// The brand's tokens.
    package struct Tokens: Sendable, Equatable {
        package var primary: RGBColor
        package var onPrimary: RGBColor
        package var primarySoft: RGBColor
        package var primaryLine: RGBColor
        package var headerFrom: RGBColor
        package var headerTo: RGBColor
        package var headerText: RGBColor
    }

    /// The server's rules, for when it sent no colours or the app chose its own: in dark mode the primary is one step
    /// lighter; on_primary is white unless white is under 4.5:1; soft and line are the primary at 10% and 22% over
    /// the background; the header runs from the brand colour to one step darker, in dark mode to two steps darker
    /// (so the brand's own colour, with white text on it, stays at the top). A step is 10 points of HSL lightness.
    package static func derive(_ base: RGBColor, dark: Bool) -> Tokens {
        let background = dark ? hex("#121316") : .white
        let primary = dark ? base.steps(1) : base
        let from = base
        let to = base.steps(dark ? -2 : -1)
        return Tokens(primary: primary, onPrimary: readableText(on: primary),
                      primarySoft: primary.over(background, opacity: 0.10),
                      primaryLine: primary.over(background, opacity: 0.22),
                      headerFrom: from, headerTo: to, headerText: headerText(on: from, to))
    }

    /// White when it reaches 3:1 on both header colours, else #1B1D21 (APPEARANCE-CONTRACT § 1, header_text).
    package static func headerText(on from: RGBColor, _ to: RGBColor) -> RGBColor {
        from.contrast(with: .white) >= 3 && to.contrast(with: .white) >= 3 ? .white : hex("#1B1D21")
    }

    private static func hex(_ value: String) -> RGBColor {
        RGBColor(hex: value) ?? .black
    }

    /// The config's `theme.mode` (or the app's `Clomni.setTheme`) wins over the system's appearance unless it says
    /// `system`.
    package static func isDark(_ mode: MessengerConfig.Mode?, systemIsDark: Bool) -> Bool {
        switch mode {
        case .dark?: return true
        case .light?: return false
        default: return systemIsDark
        }
    }

    /// White when it reaches 4.5:1 (WCAG AA for body text) on `background`, otherwise black, which then always does:
    /// one of the two reaches at least 4.58:1 on any colour.
    package static func readableText(on background: RGBColor) -> RGBColor {
        background.contrast(with: .white) >= 4.5 ? .white : .black
    }
}

/// The app's `Clomni.setTheme`: each field it gave wins over the panel; nil leaves the panel's.
package struct ThemeOverride: Sendable, Equatable {
    /// "#RRGGBB"; the tokens are then derived in the SDK by the server's rules.
    package var primaryColor: String?
    package var mode: MessengerConfig.Mode?

    package init(primaryColor: String? = nil, mode: MessengerConfig.Mode? = nil) {
        self.primaryColor = primaryColor
        self.mode = mode
    }
}
