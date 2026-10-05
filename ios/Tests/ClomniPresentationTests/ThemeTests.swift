import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

// macOS's QuickDraw also declares RGBColor; this module's own name wins over both imports.
typealias RGBColor = ClomniPresentation.RGBColor

final class ThemeTests: XCTestCase {
    private let apar = RGBColor(hex: "#1F9D63")!

    /// Each channel of `actual` within `tolerance` (of 255) of the brief's example.
    private func assertClose(_ actual: RGBColor, _ expected: String, _ tolerance: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        let target = RGBColor(hex: expected)!
        let worst = [actual.red - target.red, actual.green - target.green, actual.blue - target.blue]
            .map { abs($0) * 255 }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, tolerance, "\(actual) vs \(expected)", file: file, line: line)
    }

    private func brand(_ color: String, style: String = "gradient") throws -> MessengerConfig.Brand {
        let json = #"{"brand":{"name":"Apar","primary_color":"\#(color)","header_style":"\#(style)"}}"#
        return try XCTUnwrap(ProtocolJSON.parseConfig(Data(json.utf8))).brand
    }

    func testHexAndArithmetic() {
        XCTAssertEqual(apar.hex, "#1F9D63")
        XCTAssertEqual(apar.description, "#1F9D63")
        for bad in ["1F9D63", "#1F9D6", "#1F9D6Z", "#1F9D6300", "#+12345", "#-12345", "# 12345", "#１Ｆ９Ｄ６３", "#1F9D6\n", ""] {
            XCTAssertNil(RGBColor(hex: bad), bad)
        }
        XCTAssertEqual(RGBColor(hex: "#0a66c2")?.hex, "#0A66C2", "lower case is hex too")
        XCTAssertEqual(RGBColor(red: 2, green: -1, blue: 0.5).hex, "#FF0080", "channels are clamped")
        XCTAssertEqual(RGBColor.white.contrast(with: .black), 21, accuracy: 0.001)
        XCTAssertEqual(apar.contrast(with: apar), 1, accuracy: 0.001)
        XCTAssertEqual(apar.contrast(with: .white), 3.46, accuracy: 0.01)
        XCTAssertEqual(RGBColor.black.over(.white, opacity: 0.5).hex, "#808080")
        for hex in ["#1F9D63", "#E5484D", "#0A66C2", "#FFFFFF", "#000000", "#808080", "#FF00FF", "#FFFF00", "#00FFFF"] {
            let color = RGBColor(hex: hex)!
            let (hue, saturation, lightness) = color.hsl
            XCTAssertEqual(RGBColor(hue: hue, saturation: saturation, lightness: lightness).hex, hex, "HSL round trip")
        }
        XCTAssertEqual(RGBColor(hue: -120, saturation: 1, lightness: 0.5).hex, "#0000FF", "hue wraps")
        XCTAssertEqual(apar.steps(20).hex, "#FFFFFF", "lightness stops at white")
    }

    /// The contract's rules (APPEARANCE-CONTRACT § 1), for a config without the server's colours: soft 10% and line
    /// 22% over the background; the header from the brand colour to one step darker (dark mode: two); dark mode's
    /// primary one step lighter.
    func testDerivedTokensFollowTheContract() throws {
        let light = ClomniTheme.make(brand: try brand("#1F9D63"), dark: false).colors
        XCTAssertEqual(light.primary, apar)
        XCTAssertEqual([light.primarySoft, light.primaryLine, light.headerFrom, light.headerTo].map(\.hex),
                       ["#E9F5EF", "#CEE9DD", "#1F9D63", "#177248"])
        XCTAssertEqual(light.primarySoft, apar.over(.white, opacity: 0.10))
        XCTAssertEqual(light.headerFrom, apar, "the brand colour itself at the top")
        XCTAssertEqual(light.headerTo, apar.steps(-1))

        let dark = ClomniTheme.make(brand: try brand("#1F9D63"), dark: true).colors
        XCTAssertEqual(dark.primary.hex, "#27C87E")
        XCTAssertEqual([dark.primarySoft, dark.primaryLine, dark.headerFrom, dark.headerTo].map(\.hex),
                       ["#142520", "#173B2D", "#1F9D63", "#0E482D"])

        let solid = ClomniTheme.make(brand: try brand("#1F9D63", style: "solid"), dark: false).colors
        XCTAssertEqual([solid.headerFrom, solid.headerTo], [apar, apar], "one colour")

        // header_text: white needs 3:1 on both header colours: 3.5:1 on Apar's #1F9D63, 5.9:1 on #177248, so the
        // brief's green header keeps its white text; dark mode's (#1F9D63 → #0E482D) too, and the solid one.
        XCTAssertEqual(light.headerText, .white)
        XCTAssertEqual(dark.headerText, .white)
        XCTAssertEqual(solid.headerText, .white)
        XCTAssertEqual(ClomniTheme.headerText(on: RGBColor(hex: "#FFD60A")!, RGBColor(hex: "#5A2D82")!).hex, "#1B1D21",
                       "both colours must carry it")
        let picture = try XCTUnwrap(ProtocolJSON.parseConfig(Data(
            ##"{"brand":{"primary_color":"#FFD60A","header_style":"image","header_image_url":"https://a.az/h.png"}}"##.utf8)))
        XCTAssertEqual(ClomniTheme.make(brand: picture.brand, dark: false).colors.headerText, .white,
                       "over a picture's dark veil, always white")
    }

    /// The server's colours win over the SDK's own arithmetic, so Android and iOS show the same.
    func testTheServersColoursWin() throws {
        // Fixture 42: the server's own palette for Apar.
        let apar = Fixture.aparConfig
        let light = ClomniTheme.make(brand: apar.brand, dark: false).colors
        XCTAssertEqual([light.primary, light.onPrimary, light.primarySoft, light.primaryLine, light.headerFrom,
                        light.headerTo, light.headerText].map(\.hex),
                       ["#1F9D63", "#000000", "#E9F5EF", "#CEE9DD", "#1F9D63", "#177248", "#FFFFFF"])
        let dark = ClomniTheme.make(brand: apar.brand, dark: true).colors
        XCTAssertEqual([dark.primary, dark.onPrimary, dark.primarySoft, dark.primaryLine, dark.headerFrom, dark.headerTo,
                        dark.headerText].map(\.hex),
                       ["#27C87E", "#000000", "#142520", "#173B2D", "#1F9D63", "#0E482D", "#FFFFFF"],
                       "the dark header's text is not on_primary's black")
        // Colours the SDK would never work out itself, and no header_text (a server older than it):
        // every one is taken as sent, header_text worked out from the header colours.
        let older = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"primary_color":"#1F9D63","colors":{
              "light":{"primary":"#1F9D63","on_primary":"#FFFFFF","primary_soft":"#E9F5EF","primary_line":"#C6E6D5",
                       "header_from":"#3FB37C","header_to":"#13734A"},
              "dark":{"primary":"#34B57A","on_primary":"#0B0C0E","primary_soft":"#16241D","primary_line":"#24503A",
                      "header_from":"#1F9D63","header_to":"#0E4F33"}}}}
            """##.utf8)))
        XCTAssertNil(older.brand.colors?.light.headerText)
        let olderLight = ClomniTheme.make(brand: older.brand, dark: false).colors
        XCTAssertEqual([olderLight.onPrimary, olderLight.primaryLine, olderLight.headerFrom, olderLight.headerTo].map(\.hex),
                       ["#FFFFFF", "#C6E6D5", "#3FB37C", "#13734A"])
        let olderDark = ClomniTheme.make(brand: older.brand, dark: true).colors
        XCTAssertEqual([olderDark.primary, olderDark.onPrimary, olderDark.headerTo].map(\.hex), ["#34B57A", "#0B0C0E", "#0E4F33"])
        XCTAssertEqual(ClomniTheme.make(brand: older.brand, dark: false).colors.headerText.hex, "#1B1D21")
        XCTAssertEqual(ClomniTheme.make(brand: older.brand, dark: true).colors.headerText, .white)

        // Clomni.setTheme's colour wins over both: derived here from it.
        let own = ClomniTheme.make(brand: apar.brand, dark: false, primaryColor: "#0A66C2").colors
        XCTAssertEqual(own.primary.hex, "#0A66C2")
        XCTAssertEqual(own.headerFrom.hex, "#0A66C2")
        XCTAssertEqual(own.headerTo, RGBColor(hex: "#0A66C2")!.steps(-1))
        XCTAssertEqual(ClomniTheme.make(brand: apar.brand, dark: false, primaryColor: "blue").colors.primary.hex,
                       "#1F9D63", "an unreadable colour is ignored")

        // The mode: the app's, else the panel's, else the system's.
        let panelDark = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"theme":{"mode":"dark"}}"#.utf8)))
        XCTAssertTrue(ClomniTheme.make(config: panelDark, systemIsDark: false).isDark)
        XCTAssertFalse(ClomniTheme.make(config: panelDark, systemIsDark: true,
                                        override: ThemeOverride(mode: .light)).isDark)
        XCTAssertTrue(ClomniTheme.make(config: apar, systemIsDark: true).isDark)
        XCTAssertEqual(ClomniTheme.make(config: apar, systemIsDark: false,
                                        override: ThemeOverride(primaryColor: "#0A66C2")).colors.primary.hex, "#0A66C2")
    }

    /// No config yet and no setTheme colour: grey, never Clomni's green (DESIGN-PASS A). With setTheme's colour, it.
    func testNoConfigIsNeutral() {
        for dark in [false, true] {
            let theme = ClomniTheme.make(config: nil, systemIsDark: dark)
            XCTAssertEqual(theme, ClomniTheme.neutral(dark: dark))
            XCTAssertEqual(theme.colors.headerFrom, theme.colors.surface)
            XCTAssertEqual(theme.colors.primary, theme.colors.textSecondary)
            XCTAssertNotEqual(theme.colors.primary.hex, MessengerConfig.Brand.defaultPrimaryColor)
            XCTAssertGreaterThanOrEqual(theme.colors.headerFrom.contrast(with: theme.colors.headerText), 4.5)
        }
        let own = ClomniTheme.make(config: nil, systemIsDark: false, override: ThemeOverride(primaryColor: "#0A66C2"))
        XCTAssertEqual(own.colors.primary.hex, "#0A66C2", "setTheme's colour from the first frame")
        let blue = ClomniTheme.make(config: nil, systemIsDark: false, override: ThemeOverride(primaryColor: "blue"))
        XCTAssertEqual(blue, ClomniTheme.neutral(dark: false))
    }

    /// primary_strong (Home's first greeting line): the server's, else 20 points darker, or lighter for a brand
    /// white reads on at 7:1; the same in both modes; setTheme's colour gets the rule.
    func testPrimaryStrong() throws {
        let apar = Fixture.aparConfig
        XCTAssertEqual(ClomniTheme.make(brand: apar.brand, dark: false).colors.primaryStrong.hex, "#0E482D", "the server's")
        XCTAssertEqual(ClomniTheme.make(brand: apar.brand, dark: true).colors.primaryStrong.hex, "#0E482D")
        let older = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"{"brand":{"primary_color":"#1F9D63"}}"##.utf8)))
        let green = RGBColor(hex: "#1F9D63")!
        XCTAssertEqual(ClomniTheme.make(brand: older.brand, dark: false).colors.primaryStrong, green.steps(-2))
        XCTAssertEqual(ClomniTheme.make(brand: older.brand, dark: true).colors.primaryStrong, green.steps(-2), "both modes")
        let navy = RGBColor(hex: "#0B1F3A")!
        XCTAssertGreaterThanOrEqual(navy.contrast(with: .white), 7)
        XCTAssertEqual(ClomniTheme.primaryStrong(navy), navy.steps(2), "too dark to go darker")
        let own = ClomniTheme.make(brand: apar.brand, dark: false, primaryColor: "#0A66C2").colors.primaryStrong
        XCTAssertEqual(own, RGBColor(hex: "#0A66C2")!.steps(-2), "the app's colour, not the panel's strong tone")
    }

    func testNeutralTokens() {
        let light = ClomniTheme.make(brand: nil, dark: false)
        XCTAssertFalse(light.isDark)
        XCTAssertEqual([light.colors.background, light.colors.canvas, light.colors.surface, light.colors.textPrimary,
                        light.colors.textSecondary, light.colors.unread].map(\.hex),
                       ["#FFFFFF", "#F5F6F8", "#F1F2F4", "#1B1D21", "#707480", "#E5484D"])
        XCTAssertEqual(light.colors.online.hex, "#30C26B")
        let dark = ClomniTheme.make(brand: nil, dark: true)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual([dark.colors.background, dark.colors.canvas, dark.colors.surface, dark.colors.textPrimary,
                        dark.colors.textSecondary, dark.colors.unread].map(\.hex),
                       ["#121316", "#0B0C0E", "#22242A", "#F2F3F5", "#9A9DA6", "#E5484D"])
        XCTAssertEqual(light.colors.primary.hex, "#10A670", "Clomni's colour without a config")
        // Text reaches WCAG AA (4.5:1) on the background in both themes.
        for theme in [light, dark] {
            // M9: a line is the text colour at 8%, never darker.
            XCTAssertEqual(theme.colors.border, theme.colors.textPrimary.over(theme.colors.background, opacity: 0.08))
            XCTAssertGreaterThanOrEqual(theme.colors.warning.contrast(with: theme.colors.onWarning), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.background.contrast(with: theme.colors.textPrimary), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.background.contrast(with: theme.colors.textSecondary), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.canvas.contrast(with: theme.colors.textPrimary), 4.5)
        }
        // Why "Hələ söhbət yoxdur" on the canvas uses textPrimary: the grey is under 4.5:1 there.
        XCTAssertEqual(light.colors.canvas.contrast(with: light.colors.textSecondary), 4.32, accuracy: 0.01)
        XCTAssertEqual(ClomniTheme.Radius.card, 12)
        XCTAssertEqual(ClomniTheme.Radius.homeCard, 16)
        XCTAssertEqual([ClomniTheme.Size.closeCircle, ClomniTheme.Size.closeGlyph, ClomniTheme.Size.closeStroke,
                        ClomniTheme.Size.barEdge, ClomniTheme.Size.barTop, ClomniTheme.Size.barRow], [40, 20, 2, 16, 16, 48], "one close button")
        XCTAssertEqual(ClomniTheme.Shadow.card, ClomniTheme.Shadow(opacity: 0.06, radius: 8, y: 2), "one, very light")
        XCTAssertEqual([ClomniTheme.Radius.message, ClomniTheme.Radius.messageJoined], [20, 6])
    }

    /// onPrimary, where the SDK derives it: white or black by WCAG 4.5:1.
    func testTextOnPrimary() throws {
        // White on #1F9D63 is 3.5:1, black 6.1:1.
        XCTAssertEqual(ClomniTheme.make(brand: try brand("#1F9D63"), dark: false).colors.onPrimary, .black)
        XCTAssertEqual(ClomniTheme.make(brand: try brand("#1A2B4C"), dark: false).colors.onPrimary, .white)
        XCTAssertEqual(ClomniTheme.make(brand: try brand("#FFD60A"), dark: false).colors.onPrimary, .black)
        // Every grey from black to white, and a few brand colours, get text at 4.5:1 or more.
        let greys = (0...255).map { RGBColor(red: Double($0) / 255, green: Double($0) / 255, blue: Double($0) / 255) }
        let brands = ["#1F9D63", "#10A670", "#0A66C2", "#E5484D", "#FFD60A", "#5A2D82"].compactMap { RGBColor(hex: $0) }
        for background in greys + brands {
            let text = ClomniTheme.readableText(on: background)
            XCTAssertGreaterThanOrEqual(background.contrast(with: text), 4.5, "\(background)")
        }
    }

    func testAppearance() {
        XCTAssertTrue(ClomniTheme.isDark(.dark, systemIsDark: false))
        XCTAssertFalse(ClomniTheme.isDark(.light, systemIsDark: true))
        XCTAssertTrue(ClomniTheme.isDark(.system, systemIsDark: true))
        XCTAssertFalse(ClomniTheme.isDark(nil, systemIsDark: false))
    }
}
