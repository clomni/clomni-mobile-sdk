import XCTest

/// The messenger's conversation on a simulator, in the page sheet the SDK presents, driven like a user
/// (DESIGN-PASS-3 H1, H2, H4). Where the keyboard is and what it covers is measured on screen, not assumed: the
/// operator's iPhone showed the keyboard over a form field while the code thought the list had moved.
/// Every test keeps screenshots (with the keyboard up) in the result bundle; CI uploads them.
@MainActor
final class KeyboardTests: XCTestCase {
    private var app: XCUIApplication!
    /// Under the last message when the list is at its end: ChatTranscript's bottom padding (Space.s).
    private static let listBottomPadding: CGFloat = 8

    private func launch(_ arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"] + arguments
        app.launch()
    }

    /// A long conversation opens at its end (what the cache kept), and the history that comes after it, in two pages
    /// above, does not take it away from there: looked at all along, the last item stays over the composer and the
    /// first message is far up, out of sight (operator's iPhone, CM-087). The demo holds the history back until 20 s
    /// after the launch, so that it comes while the test looks, not while the app is being launched.
    func testItOpensAtTheEndWhileTheHistoryComes() {
        let historyAt = Date().addingTimeInterval(20)
        launch(["-ClomniDemoHistoryAt", String(historyAt.timeIntervalSince1970)])
        let submit = element("clomni.form.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 15), "the conversation opens at its end, the form there")
        let composer = element("clomni.composer")
        var last = settled(submit)
        keep("opened-at-the-end")
        XCTAssertLessThanOrEqual(last.maxY, settled(composer).minY, "the last item \(last) is over the composer")
        XCTAssertGreaterThan(last.minY, 0, "and on screen")
        // Both pages come (at historyAt and 0.8 s later) while this looks; at every look the end is where it was.
        while Date() < historyAt.addingTimeInterval(4) {
            // What the screen showed when the end was lost, for the result bundle and CI's screenshots.
            if !submit.exists { keep("history-lost") }
            XCTAssertTrue(submit.exists, "the end stays in sight while the history comes")
            let frame = submit.frame, bar = composer.frame
            if frame.maxY > bar.minY || frame.minY <= 0 { keep("history-lost") }
            XCTAssertLessThanOrEqual(frame.maxY, bar.minY, "the last item \(frame) is over the composer \(bar)")
            XCTAssertGreaterThan(frame.minY, 0, "and on screen")
        }
        last = settled(submit)
        keep("history-came")
        XCTAssertLessThanOrEqual(last.maxY, settled(composer).minY, "the last item \(last) is over the composer")
        XCTAssertGreaterThan(last.minY, 0)
        let first = labelled("Salam, kartla ödəniş keçmir")
        XCTAssertFalse(first.exists && first.isHittable, "the first message is out of sight")
    }

    /// H1: a form field tapped near the bottom goes up with the keyboard and stays over it, the composer too.
    func testAFormFieldStaysOverTheKeyboard() {
        launch()
        let email = element("clomni.form.email")
        XCTAssertTrue(email.waitForExistence(timeout: 15), "the demo conversation and its form are on screen")
        email.tap()
        keep("form-field-tapped")
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
        // At the list's very end: its bottom padding shows between the bubble and the composer (operator, build 8).
        let bar = settled(element("clomni.composer"))
        XCTAssertEqual(bar.minY - bubble.maxY, Self.listBottomPadding, accuracy: 2,
                       "the sent message \(bubble) stands the list's padding over the composer \(bar)")
    }

    /// The last item stays just over the composer while the keyboard comes up and while the composer grows to three
    /// lines; what is sent then stands at the end, the list's padding over the composer (operator's iPhone, CM-087).
    func testTheEndStaysOverAComposerGrowingToThreeLines() {
        launch()
        let field = element("clomni.composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        let submit = element("clomni.form.submit")
        let composer = element("clomni.composer")
        field.tap()
        let keyboard = settledKeyboard()
        var last = settled(submit)
        keep("end-over-keyboard")
        XCTAssertLessThanOrEqual(last.maxY, keyboard.minY, "the last item \(last) is over the keyboard \(keyboard)")
        XCTAssertLessThanOrEqual(last.maxY, settled(composer).minY, "and over the composer")
        XCTAssertGreaterThan(last.minY, 0)

        let oneLine = settled(field).height
        field.typeText("Birinci sətir\nİkinci sətir\nÜçüncü sətir")
        let threeLines = settled(field)
        XCTAssertGreaterThan(threeLines.height, oneLine + 30, "the composer grew to three lines")
        last = settled(submit)
        keep("end-over-three-lines")
        XCTAssertLessThanOrEqual(last.maxY, settled(composer).minY, "the last item \(last) is over the grown composer")
        XCTAssertGreaterThan(last.minY, 0)

        element("clomni.composer.send").tap()
        let sent = labelled("Üçüncü sətir")
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        let bubble = settled(sent)
        keep("three-lines-sent")
        let bar = settled(composer)
        XCTAssertEqual(bar.minY - bubble.maxY, Self.listBottomPadding, accuracy: 2,
                       "the sent message \(bubble) stands the list's padding over the composer \(bar)")
    }

    /// H2: an answer that comes while the user reads further up does not pull the list; "Yeni mesaj ↓" shows, and
    /// takes the user to it.
    func testANewMessageWhileReadingAbove() {
        launch()
        let composer = element("clomni.composer.field")
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        _ = settledKeyboard()
        // The demo answers a question ten seconds later. Before that, the user drags the list 350 back into the
        // history, well past the 120 that still counts as the end, and the drag is over (held, so it does not fling
        // to the top and pull the sheet down).
        composer.typeText("Kuryer nə vaxt gələcək?")
        element("clomni.composer.send").tap()
        XCTAssertTrue(labelled("Kuryer nə vaxt gələcək?").waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 350)), withVelocity: .default,
                    thenHoldForDuration: 0.3)
        keep("reading-above")
        let capsule = element("clomni.chat.newMessage")
        XCTAssertTrue(capsule.waitForExistence(timeout: 20), "\"Yeni mesaj\" shows")
        let answer = labelled("Bəli, yoxlayıb")
        XCTAssertFalse(answer.exists && answer.isHittable, "the list stayed where the user reads")
        keep("new-message-capsule")
        capsule.tap()
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let frame = settled(answer)
        keep("new-message-shown")
        XCTAssertLessThanOrEqual(frame.maxY, settled(composer).minY, "the answer \(frame) is in sight over the composer")
        let bar = settled(element("clomni.composer"))
        XCTAssertEqual(bar.minY - frame.maxY, Self.listBottomPadding, accuracy: 2,
                       "at the end, the list's padding between the answer \(frame) and the composer \(bar)")
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

    /// In the result bundle, and as `<name>.png` in CLOMNI_SCREENSHOTS on the Mac when it is set (CI sets it as
    /// TEST_RUNNER_CLOMNI_SCREENSHOTS and uploads that folder).
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
