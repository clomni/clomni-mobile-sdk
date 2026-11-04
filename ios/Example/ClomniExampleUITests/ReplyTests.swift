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

        // A drag to the right on the user's own message, from 60 pt off the screen's edge to the edge: all the room
        // a message on the right has. TestFlight #21 needed 80 pt of finger, more than a short message ever has.
        let window = app.windows.firstMatch.frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.maxX - 60, dy: settled(mine).midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 56, dy: 0)), withVelocity: .default,
                    thenHoldForDuration: 0.1)
        XCTAssertTrue(quote("Siz").waitForExistence(timeout: 5), "a drag to the right answers the user's own message")
        XCTAssertTrue(quote("Çox sağ olun").exists)
        keep("own-swiped")

        // Taken off with the quote's ✕; then "Cavabla" in its long-press menu quotes it again.
        app.descendants(matching: .any).matching(identifier: "clomni.composer").firstMatch.buttons["Bağla"].tap()
        XCTAssertTrue(quote("Siz").waitForNonExistence(timeout: 5), "the quote is gone")
        mine.press(forDuration: 1.2)
        let reply = app.buttons["Cavabla"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "the user's own message has Cavabla")
        keep("own-menu")
        reply.tap()
        XCTAssertTrue(quote("Siz").waitForExistence(timeout: 5), "quoted over the field, by Siz")
        keep("own-quoted")
    }

    /// An element's frame once two looks 0.25 s apart agree.
    private func settled(_ element: XCUIElement) -> CGRect {
        var last = CGRect.null
        for _ in 0..<16 {
            Thread.sleep(forTimeInterval: 0.25)
            let frame = element.frame
            if frame == last { return frame }
            last = frame
        }
        return last
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
