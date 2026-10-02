import Foundation

/// The panel's pictures come in a few widths and as WebP (APPEARANCE-CONTRACT § 1): `?w=48|96|144` for logos and
/// avatars, `?w=360|720|1080` for the header picture, `&format=webp`. The SDK asks for the smallest width that covers
/// the picture on this screen (a 28 pt logo at @3x → 96), the largest when none does.
package enum ImageSizing {
    package enum Kind: Sendable {
        case icon, header
        /// The full logo (APPEARANCE-CONTRACT § 4a).
        case wordmark

        var widths: [Int] {
            switch self {
            case .icon: return [48, 96, 144]
            case .header: return [360, 720, 1080]
            case .wordmark: return [300, 600, 1200]
            }
        }
    }

    package static func url(_ url: URL, kind: Kind, points: Double, scale: Double) -> URL {
        let pixels = Int((points * scale).rounded(.up))
        let width = kind.widths.first { $0 >= pixels } ?? kind.widths[kind.widths.count - 1]
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "w" && $0.name != "format" }
        items.append(URLQueryItem(name: "w", value: String(width)))
        items.append(URLQueryItem(name: "format", value: "webp"))
        components.queryItems = items
        return components.url ?? url
    }
}
