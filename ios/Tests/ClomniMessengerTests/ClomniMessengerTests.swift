import Foundation
import XCTest
import ClomniMessenger

final class ClomniMessengerTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testVersionMatchesThePodspec() throws {
        let text = try String(contentsOf: root.appendingPathComponent("ClomniMessenger.podspec"), encoding: .utf8)
        XCTAssertTrue(text.contains("s.version = '\(Clomni.version)'"), "ClomniMessenger.podspec and Clomni.version differ")
    }

    /// CocoaPods compiles every target into one module, where two files with one name do not build.
    func testNoTwoSourceFilesShareAName() throws {
        let sources = root.appendingPathComponent("ios/Sources")
        let names = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path))
            .compactMap { ($0 as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
            .filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(names.count, 10)
        XCTAssertEqual(Dictionary(grouping: names) { $0 }.filter { $0.value.count > 1 }.keys.sorted(), [])
    }
}
