import Foundation

/// Sizes and labels of images and files in the conversation (brief 8 · 7.4, 8 · 5.5).
public enum Media {
    public static let maxImageWidth: Double = 220
    public static let maxImageHeight: Double = 300
    /// Images are scaled so their longer side is at most this many pixels before they are sent.
    public static let maxUploadSide: Double = 2048

    /// The box an image takes in its bubble, reserved before it loads so the list does not jump: its own ratio
    /// within 220×300 (never larger than the image), or a 4:3 placeholder when the size is unknown.
    public static func imageBox(width: Int?, height: Int?) -> (width: Double, height: Double, known: Bool) {
        guard let width, let height, width > 0, height > 0 else {
            return (maxImageWidth, maxImageWidth * 3 / 4, false)
        }
        let scale = min(1, maxImageWidth / Double(width), maxImageHeight / Double(height))
        return ((Double(width) * scale).rounded(), (Double(height) * scale).rounded(), true)
    }

    /// The pixel size to send an image of `width`×`height` at.
    public static func uploadSize(width: Double, height: Double) -> (width: Double, height: Double) {
        let scale = min(1, maxUploadSide / max(width, height, 1))
        return ((width * scale).rounded(), (height * scale).rounded())
    }

    /// "820 B", "182 KB", "1,4 MB" (a decimal point in English).
    public static func fileSize(_ bytes: Int, language: String) -> String {
        switch bytes {
        case ..<1_000: return "\(max(0, bytes)) B"
        case ..<1_000_000: return "\(Int((Double(bytes) / 1_000).rounded())) KB"
        default:
            let megabytes = String(format: "%.1f", Double(bytes) / 1_000_000)
            return (language == "en" ? megabytes : megabytes.replacingOccurrences(of: ".", with: ",")) + " MB"
        }
    }

    /// The SF Symbol of a file card.
    public static func fileSymbol(mime: String) -> String {
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("video/") { return "film" }
        return "doc"
    }

    public static func isImage(mime: String) -> Bool {
        mime.hasPrefix("image/")
    }
}
