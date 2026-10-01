import Foundation

/// An sRGB colour, with the arithmetic the theme derives its tokens with.
package struct RGBColor: Sendable, Hashable, CustomStringConvertible {
    /// 0…1.
    package let red: Double
    package let green: Double
    package let blue: Double

    package init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// "#RRGGBB".
    package init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    package static let white = RGBColor(red: 1, green: 1, blue: 1)
    package static let black = RGBColor(red: 0, green: 0, blue: 0)

    package var hex: String {
        let channels = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    package var description: String { hex }

    /// WCAG 2 relative luminance.
    package var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1…21.
    package func contrast(with other: RGBColor) -> Double {
        let (light, dark) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (light + 0.05) / (dark + 0.05)
    }

    /// One step of the brand palette is 10 points of HSL lightness: `steps(-1)` is the darker tone of the header,
    /// `steps(1)` the lighter one dark mode uses.
    package func steps(_ count: Int) -> RGBColor {
        let (hue, saturation, lightness) = hsl
        return RGBColor(hue: hue, saturation: saturation, lightness: lightness + 0.1 * Double(count))
    }

    /// This colour at `opacity` over `background`.
    package func over(_ background: RGBColor, opacity: Double) -> RGBColor {
        RGBColor(red: red * opacity + background.red * (1 - opacity),
                 green: green * opacity + background.green * (1 - opacity),
                 blue: blue * opacity + background.blue * (1 - opacity))
    }

    /// Hue 0…360, saturation and lightness 0…1.
    package var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        return (hue, saturation, lightness)
    }

    package init(hue: Double, saturation: Double, lightness: Double) {
        let saturation = min(1, max(0, saturation))
        let lightness = min(1, max(0, lightness))
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch sector {
        case ..<1: (r, g, b) = (chroma, second, 0)
        case ..<2: (r, g, b) = (second, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, second)
        case ..<4: (r, g, b) = (0, second, chroma)
        case ..<5: (r, g, b) = (second, 0, chroma)
        default: (r, g, b) = (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        self.init(red: r + match, green: g + match, blue: b + match)
    }
}
