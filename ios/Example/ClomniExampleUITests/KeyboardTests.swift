import XCTest

/// The messenger's conversation on a simulator, in the page sheet the SDK presents, driven like a user
/// (DESIGN-PASS-3 H1, H2, H4). Where the keyboard is and what it covers is measured on screen, not assumed: the
/// operator's iPhone showed the keyboard over a form field while the code thought the list had moved.
/// Every test keeps screenshots (with the keyboard up) in the result bundle; CI uploads them.
@MainActor
final class KeyboardTests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"]
        app.launch()
    }

    /// H1: a form field tapped near the bottom goes up with the keyboard and stays over it, the composer too.
    func testAFormFieldStaysOverTheKeyboard() {
        launch()
        let email = element("clomni.form.email")
        XCTAssertTrue(email.waitForExistence(timeout: 15), "the demo conversation and its form are on screen")
        email.tap()
        let keyboard = settledKeyboard()
        keep("form-field-over-keyboard")
        let field = settled(email)
        XCTAssertLessThanOrEqual(field.maxY, keyboard.minY, "the field \(field) is over the keyboard \(keyboard)")
        XCTAssertGreaterThan(field.minY, 0, "and on screen")
        XCTAssertLessThanOrEqual(element("clomni.composer.field").frame.maxY, keyboard.minY, "the composer is over it")
    }

    /// H1, H2, H4: with the composer focused the end of the conversation (the form's button) is over the keyboard;
    /// a message sent goes to the end and stands over the keyboard, small time and ✓ in its corner.
    func testTheLastMessageStaysOverTheKeyboard() {
        launch()
        let composer = element("clomni.composer.field")
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        let keyboard = settledKeyboard()
        keep("composer-focused")
        let field = settled(composer)
        XCTAssertLessThanOrEqual(field.maxY, keyboard.minY, "the composer \(field) is over the keyboard \(keyboard)")
        let submit = settled(element("clomni.form.submit"))
        XCTAssertLessThanOrEqual(submit.maxY, field.minY, "the last item \(submit) is over the composer \(field)")
        XCTAssertGreaterThan(submit.minY, 0)

        composer.typeText("Kuryer gəldi")
        element("clomni.composer.send").tap()
        let sent = labelled("Kuryer gəldi")
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        let bubble = settled(sent)
        keep("message-sent")
        XCTAssertLessThanOrEqual(bubble.maxY, settledKeyboard().minY, "the sent message \(bubble) is over the keyboard")
        XCTAssertLessThanOrEqual(bubble.maxY, settled(composer).minY, "and over the composer")
    }

    /// H2: an answer that comes while the user reads further up does not pull the list; "Yeni mesaj ↓" shows, and
    /// takes the user to it.
    func testANewMessageWhileReadingAbove() {
        launch()
        let composer = element("clomni.composer.field")
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        _ = settledKeyboard()
        // The demo answers a question four seconds later; meanwhile the user drags the list 260 down, back into the
        // history. Slowly and held, so it does not fling to the top and pull the sheet down.
        composer.typeText("Kuryer nə vaxt gələcək?")
        element("clomni.composer.send").tap()
        let question = labelled("Kuryer nə vaxt gələcək?")
        XCTAssertTrue(question.waitForExistence(timeout: 3))
        let start = question.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 260)), withVelocity: .slow,
                    thenHoldForDuration: 0.2)
        let capsule = element("clomni.chat.newMessage")
        XCTAssertTrue(capsule.waitForExistence(timeout: 10), "\"Yeni mesaj\" shows")
        let answer = labelled("Bəli, yoxlayıb")
        XCTAssertFalse(answer.exists && answer.isHittable, "the list stayed where the user reads")
        keep("new-message-capsule")
        capsule.tap()
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let frame = settled(answer)
        keep("new-message-shown")
        XCTAssertLessThanOrEqual(frame.maxY, settled(composer).minY, "the answer \(frame) is in sight over the composer")
        XCTAssertFalse(capsule.exists, "the capsule is gone")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The software keyboard's frame once it has come up and stopped moving.
    private func settledKeyboard(file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10),
                      "the software keyboard shows (the simulator's hardware keyboard must be off)", file: file, line: line)
        return settled(keyboard)
    }

    /// An element's frame once two looks 0.25 s apart agree: the keyboard's spring and the list's scroll are over.
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

    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
