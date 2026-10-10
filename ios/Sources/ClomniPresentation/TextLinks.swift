import Foundation

/// Web addresses, emails and phone numbers written as plain text in a message, made tappable (CM-087): `https://`,
/// `http://` and `www.` addresses, a bare domain of a known top-level domain (`clomni.ai`, `example.com.az/qiymet`),
/// `name@domain.tld`, and `+994…` or any 9 to 15 digits (spaces, dashes and parentheses between them). A scanner of its own rather than NSDataDetector, which Linux's Foundation lacks: the
/// same rules on every platform, and tested where the tests run.
package enum TextLinks {
    package struct Match: Sendable, Equatable {
        package let range: Range<String.Index>
        package let url: URL
    }

    /// The runs with what `detect` finds turned into links; a run that is a link already (markdown) stays as it is.
    package static func linkify(_ runs: [TextRun]) -> [TextRun] {
        runs.flatMap { run -> [TextRun] in
            let matches = run.link == nil ? detect(run.text) : []
            guard !matches.isEmpty else { return [run] }
            var parts: [TextRun] = []
            var cursor = run.text.startIndex
            func plain(_ end: String.Index) {
                if cursor < end { parts.append(TextRun(String(run.text[cursor..<end]), bold: run.bold, italic: run.italic)) }
            }
            for match in matches {
                plain(match.range.lowerBound)
                parts.append(TextRun(String(run.text[match.range]), bold: run.bold, italic: run.italic, link: match.url))
                cursor = match.range.upperBound
            }
            plain(run.text.endIndex)
            return parts
        }
    }

    /// The links in `text`, in order and never overlapping.
    package static func detect(_ text: String) -> [Match] {
        let chars = Array(text)
        var bounds = Array(text.indices)
        bounds.append(text.endIndex)
        var found: [(start: Int, end: Int, url: URL)] = []

        // Addresses and emails sit inside one word.
        var start = 0
        while start < chars.count {
            guard !chars[start].isWhitespace else { start += 1; continue }
            var end = start
            while end < chars.count, !chars[end].isWhitespace { end += 1 }
            if let link = address(chars, start, end) ?? email(chars, start, end) ?? domain(chars, start, end) {
                found.append(link)
            }
            start = end
        }
        // A phone number may run over several words; never inside an address or email.
        var index = 0
        while index < chars.count {
            if let taken = found.first(where: { $0.start <= index && index < $0.end }) {
                index = taken.end
                continue
            }
            if let phone = phone(chars, index), !found.contains(where: { $0.start < phone.end && phone.start < $0.end }) {
                found.append(phone)
                index = phone.end
            } else {
                index += 1
            }
        }
        return found.sorted { $0.start < $1.start }.map { Match(range: bounds[$0.start]..<bounds[$0.end], url: $0.url) }
    }

    // MARK: - Addresses

    private static let prefixes = ["https://", "http://", "www."]
    /// Punctuation that ends a sentence or closes a quote, not the address it follows.
    private static let trailing: Set<Character> = [".", ",", ":", ";", "!", "?", "\"", "'", "»", "”", "’", ">", "]", "}", "…"]

    private static func address(_ chars: [Character], _ start: Int, _ end: Int) -> (start: Int, end: Int, url: URL)? {
        guard let from = (start..<end).first(where: { index in
            let head = String(chars[index..<min(end, index + 8)]).lowercased()
            return prefixes.contains { head.hasPrefix($0) }
        }) else { return nil }
        // "awww.az" is no address; "(https://…" and "sayt:https://…" are.
        if from > start, chars[from - 1].isLetter || chars[from - 1].isNumber { return nil }
        var to = end
        while to > from {
            let last = chars[to - 1]
            if trailing.contains(last) {
                to -= 1
            } else if last == ")", chars[from..<to].filter({ $0 == ")" }).count > chars[from..<to].filter({ $0 == "(" }).count {
                // A closing parenthesis the address did not open: "(bax: https://example.com)".
                to -= 1
            } else {
                break
            }
        }
        let raw = String(chars[from..<to])
        let lower = raw.lowercased()
        let isWWW = lower.hasPrefix("www.")
        let rest = raw.dropFirst(isWWW ? 0 : lower.hasPrefix("https://") ? 8 : 7)
        let host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        // A host with a dot inside it ("www." needs one more after itself).
        let named = isWWW ? host.dropFirst(4) : host
        guard named.contains("."), named.first != ".", named.last != ".", !named.contains("..") else { return nil }
        guard let url = webURL(isWWW ? "https://" + raw : raw) else { return nil }
        return (from, to, url)
    }

    // MARK: - Bare domains

    /// The top-level domains a bare domain may end in. A list rather than "any letters": "fayl.txt", "e.g." or
    /// "Ad.Soyad" are no addresses, and "1.5" or "v1.0" never were.
    private static let topLevelDomains: Set<String> = [
        "com", "net", "org", "info", "biz", "io", "ai", "app", "dev", "co", "me", "tv", "online", "site", "store",
        "shop", "tech", "cloud", "pro", "edu", "gov", "az", "ru", "tr", "ua", "by", "kz", "ge", "uz", "kg", "am",
        "eu", "uk", "us", "de", "fr", "it", "es", "nl", "pl", "ch", "at", "be", "se", "no", "dk", "fi", "cz", "ca",
        "au", "jp", "cn", "in", "ae", "sa", "qa", "il", "br",
    ]

    /// "clomni.ai", "(example.com.az/qiymet)": labels of ASCII letters, digits and dashes, the last one a known
    /// top-level domain written in lower case ("Salam.Az" starts a sentence) after a name with a letter in it, then
    /// the path as an address has it.
    private static func domain(_ chars: [Character], _ start: Int, _ end: Int) -> (start: Int, end: Int, url: URL)? {
        // Opening punctuation in front: "(clomni.ai)", "«clomni.ai»".
        var from = start
        while from < end, "([{\"'«“‘<".contains(chars[from]) { from += 1 }
        var to = from
        while to < end, chars[to].isASCII, chars[to].isLetter || chars[to].isNumber || chars[to] == "-" || chars[to] == "." {
            to += 1
        }
        // Not inside an email ("x@clomni.ai" the email has), a scheme ("https:") or a path.
        if to < end, chars[to] == "@" || chars[to] == ":" && to + 1 < end && chars[to + 1] == "/" { return nil }
        var host = String(chars[from..<to])
        while host.hasSuffix(".") { host.removeLast() }
        var labels = host.split(separator: ".", omittingEmptySubsequences: false)
        // A case ending after a dash is not the domain's: "clomni.ai-dan" is clomni.ai.
        if let last = labels.last, let dash = last.firstIndex(of: "-"), topLevelDomains.contains(String(last[..<dash])) {
            labels[labels.count - 1] = last[..<dash]
            host = labels.joined(separator: ".")
        }
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.first != "-" && $0.last != "-" }),
              let tld = labels.last, tld.allSatisfy({ $0.isLowercase }), topLevelDomains.contains(String(tld)),
              labels[labels.count - 2].contains(where: \.isLetter) else {
            // A name with a letter before the top-level domain: "3.14.az" is a number.
            return nil
        }
        // The path, as an address's: whatever follows the host in the word, less the sentence's punctuation.
        var last = from + host.count
        if last < end, "/?#".contains(chars[last]) {
            last = end
            while last > from + host.count {
                let char = chars[last - 1]
                if trailing.contains(char) || char == ")" && chars[from..<last].filter({ $0 == ")" }).count
                    > chars[from..<last].filter({ $0 == "(" }).count {
                    last -= 1
                } else {
                    break
                }
            }
        }
        guard let url = webURL("https://" + String(chars[from..<last])) else { return nil }
        return (from, last, url)
    }

    /// An address as written, letters outside ASCII ("…/ödəniş") percent-encoded so `URL` takes it.
    private static func webURL(_ raw: String) -> URL? {
        if let url = URL(string: raw) { return url }
        let allowed = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "#%"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    // MARK: - Emails

    private static func isLocal(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "._%+-".contains(char))
    }

    private static func isDomain(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || char == "." || char == "-")
    }

    private static func email(_ chars: [Character], _ start: Int, _ end: Int) -> (start: Int, end: Int, url: URL)? {
        guard let at = chars[start..<end].firstIndex(of: "@") else { return nil }
        var from = at
        while from > start, isLocal(chars[from - 1]) { from -= 1 }
        var to = at + 1
        while to < end, isDomain(chars[to]) { to += 1 }
        // A dot or dash at the end ends the sentence, not the domain.
        while to > at + 1, chars[to - 1] == "." || chars[to - 1] == "-" { to -= 1 }
        // Nothing glued in front ("ad:x@y.az" is fine, "ödə@…" is not an address).
        if from > start, chars[from - 1].isLetter || chars[from - 1].isNumber { return nil }
        let local = String(chars[from..<at])
        let domain = String(chars[(at + 1)..<to])
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard !local.isEmpty, !local.hasPrefix("."), !local.hasSuffix("."), labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }), let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              let url = URL(string: "mailto:" + local + "@" + domain) else { return nil }
        return (from, to, url)
    }

    // MARK: - Phones

    private static let phoneDigits = 9...15

    /// A number starting at `start`: a "+" or a digit with no letter or digit glued in front, then digits with at most
    /// one space, dash or parenthesis between them, ending on a digit with no letter or digit after it.
    private static func phone(_ chars: [Character], _ start: Int) -> (start: Int, end: Int, url: URL)? {
        let first = chars[start]
        guard first == "+" || first.isASCIIDigit else { return nil }
        if start > 0 {
            let before = chars[start - 1]
            if before.isLetter || before.isNumber || before == "+" || before == "/" || before == "." || before == "-" {
                return nil
            }
        }
        var digits = first == "+" ? "+" : ""
        var index = first == "+" ? start + 1 : start
        var lastDigit = -1
        var separators = 0
        while index < chars.count {
            let char = chars[index]
            if char.isASCIIDigit {
                digits.append(char)
                lastDigit = index
                separators = 0
            } else if char == " " || char == "-" || char == "(" || char == ")" {
                separators += 1
                // "(050) 123" has two in a row; more is the number's end.
                if separators > 2 || lastDigit < 0 && char != "(" { break }
            } else {
                break
            }
            index += 1
        }
        guard lastDigit >= 0 else { return nil }
        let end = lastDigit + 1
        if end < chars.count, chars[end].isLetter || chars[end].isNumber { return nil }
        let count = digits.filter(\.isASCIIDigit).count
        guard phoneDigits.contains(count), let url = URL(string: "tel:" + digits) else { return nil }
        // "(050) 123-45-67": its opening parenthesis is part of it.
        var from = start
        if from > 0, chars[from - 1] == "(", chars[from..<end].contains(")") { from -= 1 }
        return (from, end, url)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
