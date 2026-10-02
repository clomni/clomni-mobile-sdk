import Foundation
import XCTest

/// What an app can use is exactly ios/api/ClomniMessenger.txt: every `public` declaration under ios/Sources, with
/// the type it belongs to. A change to the public API fails here until that file changes with it, in the same pull
/// request, where it can be reviewed. CLOMNI_RECORD_API=1 rewrites the file.
///
/// Read from the sources rather than from the compiler, so Linux and macOS give the same list. The modules below the
/// facade declare `package`, never `public`; that is checked too, since in the CocoaPods build all of them are one
/// module with the facade.
final class PublicAPITests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testThePublicAPIIsTheReviewedOne() throws {
        let sources = root.appendingPathComponent("ios/Sources")
        var api: [String] = []
        var leaks: [String] = []
        for file in try swiftFiles(in: sources) {
            let found = PublicDeclarations.find(in: try String(contentsOf: file, encoding: .utf8))
            if file.path.contains("/ClomniMessenger/") {
                api += found
            } else {
                leaks += found.map { "\(file.lastPathComponent): \($0)" }
            }
        }
        XCTAssertEqual(leaks, [], "below the facade, declare package instead of public")

        let fixture = root.appendingPathComponent("ios/api/ClomniMessenger.txt")
        let text = api.sorted().joined(separator: "\n") + "\n"
        if ProcessInfo.processInfo.environment["CLOMNI_RECORD_API"] == "1" {
            try text.write(to: fixture, atomically: true, encoding: .utf8)
        }
        let reviewed = try String(contentsOf: fixture, encoding: .utf8)
        XCTAssertEqual(text, reviewed, "the public API changed: review it and record ios/api/ClomniMessenger.txt")
    }

    func testFindingDeclarations() {
        let source = #"""
        /// A public comment: public func nothing()
        public enum Clomni {
            public static let version: String = SDKInfo.version
            static func hidden() {}
            public static func present(source: String? = nil) { // public, but a comment
                let text = "{ public }"
            }

            public static func startFlow(_ event: String, data: [String: Any] = [:],
                                         openMessenger: Bool = false) {}
            public static var onClosed: (@MainActor @Sendable () -> Void)? {
                get { nil }
                set {}
            }
        }

        public enum Level: Sendable {
            case none, error
            case warning
            var hidden: Int { 0 }
        }

        struct Internal {
            public var odd: Int
        }

        package struct Shared {}
        @MainActor public final class Screen {}
        """#
        XCTAssertEqual(PublicDeclarations.find(in: source), [
            "enum Clomni",
            "Clomni: static let version: String",
            "Clomni: static func present(source: String? = nil)",
            "Clomni: static func startFlow(_ event: String, data: [String: Any] = [:], openMessenger: Bool = false)",
            "Clomni: static var onClosed: (@MainActor @Sendable () -> Void)?",
            "enum Level: Sendable",
            "Level: case none, error",
            "Level: case warning",
            "Internal: var odd: Int",
            "final class Screen",
        ])
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let names = try XCTUnwrap(FileManager.default.enumerator(atPath: directory.path)).compactMap { $0 as? String }
        return names.filter { $0.hasSuffix(".swift") }.sorted().map { directory.appendingPathComponent($0) }
    }
}

/// The `public` declarations of a Swift file, one line each, as "Type: declaration" inside a type. Enough Swift for
/// this SDK's own sources: comments and string contents are skipped, a declaration ends at its `{` or line end, and
/// the cases of a public enum are public too.
enum PublicDeclarations {
    static func find(in source: String) -> [String] {
        var result: [String] = []
        var types: [(name: String, depth: Int, publicEnum: Bool)] = []
        var depth = 0
        var pending: String?
        for raw in source.components(separatedBy: "\n") {
            let text = withoutComment(raw).trimmingCharacters(in: .whitespaces)
            let skeleton = withoutStrings(text)
            let owner = types.last
            if var declaration = pending {
                declaration += " " + text
                pending = finish(declaration, into: &result, owner: owner?.name)
            } else if skeleton.range(of: #"(^|\s)public\s"#, options: .regularExpression) != nil {
                pending = finish(text, into: &result, owner: owner?.name)
            } else if skeleton.hasPrefix("case "), let owner, owner.publicEnum, owner.depth == depth {
                result.append("\(owner.name): \(text)")
            }
            if let match = skeleton.range(of: #"\b(enum|struct|class|actor|protocol|extension)\s+\w+"#,
                                          options: .regularExpression),
               skeleton.hasSuffix("{") {
                let name = skeleton[match].split(separator: " ").last.map(String.init) ?? ""
                let publicEnum = skeleton.contains("public enum ")
                types.append((name, depth + 1, publicEnum))
            }
            for character in skeleton {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    while let last = types.last, last.depth > depth { types.removeLast() }
                }
            }
        }
        return result
    }

    /// Adds the declaration once it is whole (its `{`, or a line that does not end in "," or "("); else returns
    /// what there is so far.
    private static func finish(_ text: String, into result: inout [String], owner: String?) -> String? {
        let skeleton = withoutStrings(text)
        var declaration = text
        if let brace = skeleton.firstIndex(of: "{") {
            declaration = String(text[..<text.index(text.startIndex, offsetBy: skeleton.distance(from: skeleton.startIndex, to: brace))])
        } else if skeleton.hasSuffix(",") || skeleton.hasSuffix("(") {
            return text
        }
        if let modifier = declaration.range(of: "public ") {
            declaration = String(declaration[modifier.upperBound...])
        }
        declaration = declaration.trimmingCharacters(in: .whitespaces)
        // A stored constant's value is not its API.
        if declaration.contains("let "), let value = declaration.range(of: " = ") {
            declaration = String(declaration[..<value.lowerBound])
        }
        result.append(owner.map { "\($0): \(declaration)" } ?? declaration)
        return nil
    }

    private static func withoutComment(_ line: String) -> String {
        guard let range = line.range(of: #"(^|\s)//.*$"#, options: .regularExpression) else { return line }
        return String(line[..<range.lowerBound])
    }

    /// The same length, with what is inside string literals blanked.
    private static func withoutStrings(_ text: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    result.append(character)
                    continue
                }
                result.append(" ")
            } else {
                if character == "\"" { inString = true }
                result.append(character)
            }
        }
        return result
    }
}
