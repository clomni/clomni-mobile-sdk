import Foundation

/// The app's own font family (`Clomni.setTypeface`), and which of its faces each weight of the messenger uses. A
/// weight the family lacks takes its nearest face, never the system font: Regular and Bold only, semibold text is
/// Bold.
package struct Typeface: Sendable, Equatable {
    package struct Face: Sendable, Equatable {
        /// The PostScript name, for `Font.custom`.
        package let name: String
        /// 100 (thin) … 900 (black), as CSS counts.
        package let weight: Int

        package init(name: String, weight: Int) {
            self.name = name
            self.weight = weight
        }
    }

    package let family: String
    /// Upright faces, lightest first.
    package let faces: [Face]

    /// nil when the family has no upright face, which is how a family missing from the app looks: the messenger then
    /// keeps the system font.
    package init?(family: String, faces: [Face]) {
        let upright = faces.filter { !Self.isItalic($0.name) }.sorted { ($0.weight, $0.name) < ($1.weight, $1.name) }
        guard !upright.isEmpty else { return nil }
        self.family = family
        self.faces = upright
    }

    /// The face nearest to `weight`. At equal distance, semibold and heavier take the heavier face, lighter text the
    /// lighter one (as CSS does).
    package func face(for weight: Int) -> String {
        let nearest = faces.min { a, b in
            let da = abs(a.weight - weight)
            let db = abs(b.weight - weight)
            if da != db { return da < db }
            return weight >= 600 ? a.weight > b.weight : a.weight < b.weight
        }
        return (nearest ?? faces[0]).name
    }

    /// A face's weight: from its name when the name says it ("Montserrat-SemiBold"), else from the font's weight trait
    /// (UIFont.Weight, −1…1), else regular.
    package static func weight(name: String, trait: Double?) -> Int {
        weight(name: name) ?? trait.map(weight(trait:)) ?? 400
    }

    /// The weight words of font names, heaviest compounds first so "SemiBold" is not read as "Bold".
    private static let words: [(String, Int)] = [
        ("hairline", 100), ("thin", 100), ("extralight", 200), ("ultralight", 200), ("extrabold", 800),
        ("ultrabold", 800), ("semibold", 600), ("demibold", 600), ("light", 300), ("medium", 500), ("bold", 700),
        ("heavy", 800), ("black", 900), ("regular", 400), ("book", 400), ("roman", 400), ("normal", 400),
    ]

    static func weight(name: String) -> Int? {
        // The style part of a PostScript name: "Montserrat-SemiBoldItalic" → "semibolditalic".
        let style = (name.split(separator: "-").last.map(String.init) ?? name).lowercased()
        return words.first { style.contains($0.0) }?.1
    }

    /// UIFont.Weight's values: ultraLight −0.8, thin −0.6, light −0.4, regular 0, medium 0.23, semibold 0.3, bold 0.4,
    /// heavy 0.56, black 0.62.
    static func weight(trait: Double) -> Int {
        let steps: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600),
                                      (0.4, 700), (0.56, 800), (0.62, 900)]
        return steps.min { abs($0.0 - trait) < abs($1.0 - trait) }?.1 ?? 400
    }

    static func isItalic(_ name: String) -> Bool {
        let style = (name.split(separator: "-").last.map(String.init) ?? "").lowercased()
        return style.contains("italic") || style.contains("oblique")
    }
}
