import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

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
        for bad in ["1F9D63", "#1F9D6", "#1F9D6Z", "#1F9D6300"] { XCTAssertNil(RGBColor(hex: bad), bad) }
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
    /// 22% over the background; the header from one step lighter to one step darker, in dark mode from the brand
    /// colour to two steps darker; dark mode's primary one step lighter.
    func testDerivedTokensFollowTheContract() throws {
        let light = ClomniTheme.make(brand: try brand("#1F9D63"), dark: false).colors
        XCTAssertEqual(light.primary, apar)
        XCTAssertEqual([light.primarySoft, light.primaryLine, light.headerFrom, light.headerTo].map(\.hex),
                       ["#E9F5EF", "#CEE9DD", "#27C87E", "#177248"])
        XCTAssertEqual(light.primarySoft, apar.over(.white, opacity: 0.10))
        XCTAssertEqual(light.headerFrom, apar.steps(1))
        XCTAssertEqual(light.headerTo, apar.steps(-1))

        let dark = ClomniTheme.make(brand: try brand("#1F9D63"), dark: true).colors
        XCTAssertEqual(dark.primary.hex, "#27C87E")
        XCTAssertEqual([dark.primarySoft, dark.primaryLine, dark.headerFrom, dark.headerTo].map(\.hex),
                       ["#142520", "#173B2D", "#1F9D63", "#0E482D"])

        let solid = ClomniTheme.make(brand: try brand("#1F9D63", style: "solid"), dark: false).colors
        XCTAssertEqual([solid.headerFrom, solid.headerTo], [apar, apar], "one colour")
    }

    /// The server's colours win over the SDK's own arithmetic, so Android and iOS show the same.
    func testTheServersColoursWin() throws {
        let apar = Fixture.aparConfig
        let light = ClomniTheme.make(brand: apar.brand, dark: false).colors
        XCTAssertEqual([light.primary, light.onPrimary, light.primarySoft, light.primaryLine, light.headerFrom,
                        light.headerTo].map(\.hex),
                       ["#1F9D63", "#FFFFFF", "#E9F5EF", "#C6E6D5", "#3FB37C", "#13734A"])
        let dark = ClomniTheme.make(brand: apar.brand, dark: true).colors
        XCTAssertEqual([dark.primary, dark.onPrimary, dark.headerFrom, dark.headerTo].map(\.hex),
                       ["#34B57A", "#0B0C0E", "#1F9D63", "#0E4F33"])

        // Clomni.setTheme's colour wins over both: derived here from it.
        let own = ClomniTheme.make(brand: apar.brand, dark: false, primaryColor: "#0A66C2").colors
        XCTAssertEqual(own.primary.hex, "#0A66C2")
        XCTAssertEqual(own.headerFrom, RGBColor(hex: "#0A66C2")!.steps(1))
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

    func testNeutralTokens() {
        let light = ClomniTheme.make(brand: nil, dark: false)
        XCTAssertFalse(light.isDark)
        XCTAssertEqual([light.colors.background, light.colors.canvas, light.colors.surface, light.colors.textPrimary,
                        light.colors.textSecondary, light.colors.border, light.colors.unread].map(\.hex),
                       ["#FFFFFF", "#F5F6F8", "#F1F2F4", "#1B1D21", "#707480", "#E7E8EB", "#E5484D"])
        XCTAssertEqual(light.colors.online.hex, "#30C26B")
        let dark = ClomniTheme.make(brand: nil, dark: true)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual([dark.colors.background, dark.colors.canvas, dark.colors.surface, dark.colors.textPrimary,
                        dark.colors.textSecondary, dark.colors.border, dark.colors.unread].map(\.hex),
                       ["#121316", "#0B0C0E", "#22242A", "#F2F3F5", "#9A9DA6", "#2A2C32", "#E5484D"])
        XCTAssertEqual(light.colors.primary.hex, "#10A670", "Clomni's colour without a config")
        // Text reaches WCAG AA (4.5:1) on the background in both themes.
        for theme in [light, dark] {
            XCTAssertGreaterThanOrEqual(theme.colors.warning.contrast(with: theme.colors.onWarning), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.background.contrast(with: theme.colors.textPrimary), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.background.contrast(with: theme.colors.textSecondary), 4.5)
            XCTAssertGreaterThanOrEqual(theme.colors.canvas.contrast(with: theme.colors.textPrimary), 4.5)
        }
        // Why "Hələ söhbət yoxdur" on the canvas uses textPrimary: the grey is under 4.5:1 there.
        XCTAssertEqual(light.colors.canvas.contrast(with: light.colors.textSecondary), 4.32, accuracy: 0.01)
        XCTAssertEqual(ClomniTheme.Radius.card, 12)
        XCTAssertEqual(ClomniTheme.Size.cardOverlap, 40)
        XCTAssertEqual(ClomniTheme.Shadow.card.map(\.radius), [2, 10])
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
