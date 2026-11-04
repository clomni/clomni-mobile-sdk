import XCTest

/// CM-346 § 5.3 (TestFlight #21: «SDK-da öz mesajına yanıt vermək olmur»): the user answers their own message, as an
/// operator's: "Cavabla" in its long-press menu, or a drag to the right; the quote over the field says "Siz".
@MainActor
final class ReplyTests: XCTestCase {
    private var app: XCUIApplication!

    func testTheUserAnswersTheirOwnMessage() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"]
        app.launch()
        let mine = labelled("Çox sağ olun")
        XCTAssertTrue(mine.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2.5)

        mine.press(forDuration: 1.2)
        let reply = app.buttons["Cavabla"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "the user's own message has Cavabla")
        keep("own-menu")
        reply.tap()
        XCTAssertTrue(quote("Siz").waitForExistence(timeout: 5), "quoted over the field, by Siz")
        XCTAssertTrue(quote("Çox sağ olun").exists)
        keep("own-quoted")

        // Taken off with the quote's ✕, then a drag to the right on the same message quotes it again.
        app.descendants(matching: .any).matching(identifier: "clomni.composer").firstMatch.buttons["Bağla"].tap()
        XCTAssertTrue(quote("Siz").waitForNonExistence(timeout: 5), "the quote is gone")
        let start = mine.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 130, dy: 0)), withVelocity: .default,
                    thenHoldForDuration: 0.1)
        XCTAssertTrue(quote("Siz").waitForExistence(timeout: 5), "a drag to the right answers it too")
        keep("own-swiped")
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// In the quote over the field.
    private func quote(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "clomni.composer").firstMatch
            .descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// As KeyboardTests keeps them: in the result bundle, and in CLOMNI_SCREENSHOTS when it is set.
    private func keep(_ name: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        guard let folder = ProcessInfo.processInfo.environment["CLOMNI_SCREENSHOTS"], !folder.isEmpty else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
