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

    private func brand(_ color: String, onPrimary: String? = nil) throws -> MessengerConfig.Brand {
        let json = #"{"brand":{"name":"Apar","primary_color":"\#(color)""# + (onPrimary.map { #","on_primary_color":"\#($0)""# } ?? "") + "}}"
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

    /// Brief 8 · 7.1 with #1F9D63: primaryDark #13734A, primarySoft #BFE3CF, dark-mode primarySoft #2F5E46 and a
    /// one-step lighter primary (the reference draws #34B57A).
    func testDerivedColoursMatchTheBriefsExamples() throws {
        let light = ClomniTheme.make(brand: try brand("#1F9D63"), dark: false).colors
        XCTAssertEqual(light.primary, apar)
        assertClose(light.primaryDark, "#13734A", 5)
        assertClose(light.primarySoft, "#BFE3CF", 10)

        let dark = ClomniTheme.make(brand: try brand("#1F9D63"), dark: true).colors
        assertClose(dark.primarySoft, "#2F5E46", 5)
        // One step lighter: the same hue, about the same lightness as the reference; more saturated than it.
        let reference = RGBColor(hex: "#34B57A")!.hsl
        XCTAssertEqual(dark.primary.hsl.hue, reference.hue, accuracy: 1)
        XCTAssertEqual(dark.primary.hsl.lightness, reference.lightness, accuracy: 0.015)
        XCTAssertEqual(dark.primary.hex, "#27C87E")
        XCTAssertEqual(dark.primaryDark.hex, apar.hex, "the header's darker tone is the brand colour itself in dark mode")
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

    /// onPrimary: the config's colour, otherwise white or black by WCAG 4.5:1.
    func testTextOnPrimary() throws {
        XCTAssertEqual(ClomniTheme.make(brand: try brand("#1F9D63", onPrimary: "#FFFFFF"), dark: false).colors.onPrimary,
                       .white, "Apar's config says white")
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
