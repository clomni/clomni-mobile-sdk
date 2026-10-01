import Foundation
import XCTest
import ClomniMessenger

final class ClomniMessengerTests: XCTestCase {
    /// An app that imports only ClomniMessenger sees the protocol types too.
    func testReexportsTheProtocol() {
        let message = ClientMessage(clientId: "c", content: .text("Salam"))
        XCTAssertEqual(ProtocolJSON.parseClientMessage(ProtocolJSON.encode(message)), message)
    }

    func testVersionMatchesThePodspec() throws {
        let podspec = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ClomniMessenger.podspec")
        let text = try String(contentsOf: podspec, encoding: .utf8)
        XCTAssertTrue(text.contains("s.version = '\(Clomni.version)'"), "ClomniMessenger.podspec and Clomni.version differ")
    }
}
