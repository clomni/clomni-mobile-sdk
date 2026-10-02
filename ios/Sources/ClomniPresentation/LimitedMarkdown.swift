import Foundation

/// A piece of message text with one style.
package struct TextRun: Sendable, Equatable {
    package let text: String
    package let bold: Bool
    package let italic: Bool
    /// Only https:, tel: and mailto: links survive.
    package let link: URL?

    package init(_ text: String, bold: Bool = false, italic: Bool = false, link: URL? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.link = link
    }
}

/// The markdown messages may carry (brief 8 · 3): **bold**, *italic*, [text](url), line breaks and emoji. A link with
/// any other scheme (javascript:, http:, data:…) keeps its text and loses the link. A marker without its pair, or
/// with a space on its inner side ("2 * 3 * 4"), is plain text.
package enum LimitedMarkdown {
    package static let linkSchemes: Set<String> = ["https", "tel", "mailto"]

    package static func parse(_ source: String) -> [TextRun] {
        var runs: [TextRun] = []
        parse(Array(source), bold: false, italic: false, into: &runs)
        return merged(runs)
    }

    /// The text as VoiceOver and previews read it.
    package static func plainText(_ source: String) -> String {
        parse(source).map(\.text).joined()
    }

    private static func parse(_ chars: [Character], bold: Bool, italic: Bool, into runs: inout [TextRun]) {
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { runs.append(TextRun(buffer, bold: bold, italic: italic)) }
            buffer = ""
        }
        var index = 0
        while index < chars.count {
            if !bold, let close = closing(of: ["*", "*"], in: chars, from: index) {
                flush()
                parse(Array(chars[(index + 2)..<close]), bold: true, italic: italic, into: &runs)
                index = close + 2
            } else if !italic, chars[index] == "*", !(index + 1 < chars.count && chars[index + 1] == "*"),
                      let close = closing(of: ["*"], in: chars, from: index) {
                flush()
                parse(Array(chars[(index + 1)..<close]), bold: bold, italic: true, into: &runs)
                index = close + 1
            } else if chars[index] == "[", let link = link(in: chars, from: index) {
                flush()
                let url = URL(string: link.target).flatMap { url in
                    url.scheme.map { linkSchemes.contains($0.lowercased()) } == true ? url : nil
                }
                runs.append(TextRun(link.label, bold: bold, italic: italic, link: url))
                index = link.end
            } else {
                buffer.append(chars[index])
                index += 1
            }
        }
        flush()
    }

    /// Where the marker opened at `start` closes: the same marker later on, with text between that neither starts
    /// nor ends with a space.
    private static func closing(of marker: [Character], in chars: [Character], from start: Int) -> Int? {
        let width = marker.count
        guard start + width < chars.count, Array(chars[start..<(start + width)]) == marker,
              !chars[start + width].isWhitespace else { return nil }
        var index = start + width + 1
        while index + width <= chars.count {
            // Inside *italic*, a ** is bold, not the end.
            if width == 1, chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "*" {
                index += 2
                continue
            }
            if Array(chars[index..<(index + width)]) == marker, !chars[index - 1].isWhitespace {
                return index
            }
            index += 1
        }
        return nil
    }

    /// `[label](target)` starting at `start`, with balanced parentheses in the target.
    private static func link(in chars: [Character], from start: Int) -> (label: String, target: String, end: Int)? {
        guard let labelEnd = chars[(start + 1)...].firstIndex(of: "]"), labelEnd + 1 < chars.count,
              chars[labelEnd + 1] == "(" else { return nil }
        var depth = 0
        var index = labelEnd + 1
        while index < chars.count {
            if chars[index] == "(" { depth += 1 }
            if chars[index] == ")" {
                depth -= 1
                if depth == 0 {
                    let label = String(chars[(start + 1)..<labelEnd])
                    let target = String(chars[(labelEnd + 2)..<index]).trimmingCharacters(in: .whitespaces)
                    return label.isEmpty ? nil : (label, target, index + 1)
                }
            }
            if chars[index] == "\n" { return nil }
            index += 1
        }
        return nil
    }

    private static func merged(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs {
            if let last = result.last, last.bold == run.bold, last.italic == run.italic, last.link == nil, run.link == nil {
                result[result.count - 1] = TextRun(last.text + run.text, bold: run.bold, italic: run.italic)
            } else {
                result.append(run)
            }
        }
        return result
    }
}
