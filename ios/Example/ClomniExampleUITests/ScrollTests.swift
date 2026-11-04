import XCTest

/// CM-342 (Apar Ride, iPhone, iOS 18+): a drag that started on a message bubble did not move the conversation; only a
/// drag from the space beside the bubbles did. On the demo conversation, in the messenger's page sheet: a vertical drag
/// from a bubble moves the list both ways, a drag to the right on a bubble still answers it, and on a voice message a
/// vertical drag from the waveform moves the list while a drag along it moves the playhead.
@MainActor
final class ScrollTests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"]
        app.launch()
    }

    /// Down from the operator's message goes back into the history; up from the user's comes back towards the end.
    /// The sheet itself stays where it is.
    func testADragFromABubbleMovesTheList() {
        launch()
        let operatorBubble = labelled("Başqa sualınız olsa, yazın")
        XCTAssertTrue(operatorBubble.waitForExistence(timeout: 15), "the demo conversation is open at its end")
        // The history's two pages come 0.8 s apart after the opening; the list holds its end meanwhile.
        Thread.sleep(forTimeInterval: 2.5)
        let composer = element("clomni.composer")
        let bar = settled(composer)
        let before = settled(operatorBubble)
        keep("scroll-before")
        XCTAssertTrue(operatorBubble.isHittable, "the operator's message \(before) is on screen")

        drag(operatorBubble, dy: 260)
        let back = settled(operatorBubble)
        keep("scroll-down-from-a-bubble")
        XCTAssertGreaterThan(back.minY - before.minY, 150,
                             "a drag down from the bubble \(before) moved the list into the history: \(back)")
        XCTAssertEqual(settled(composer).minY, bar.minY, accuracy: 1, "the sheet stayed where it was")

        let userBubble = labelled("Çox sağ olun")
        XCTAssertTrue(userBubble.isHittable, "the user's message is on screen")
        let user = settled(userBubble)
        drag(userBubble, dy: -200)
        let forth = settled(userBubble)
        keep("scroll-up-from-a-bubble")
        XCTAssertGreaterThan(user.minY - forth.minY, 100,
                             "a drag up from the bubble \(user) moved the list towards the end: \(forth)")
        XCTAssertEqual(settled(composer).minY, bar.minY, accuracy: 1, "the sheet stayed where it was")
    }

    /// A drag to the right on a bubble quotes it over the field: "Leyla" and the message's words in the composer.
    /// (The field takes the focus with it, and the keyboard moves the list up.)
    func testADragToTheRightOnABubbleAnswersIt() {
        launch()
        let text = "Başqa sualınız olsa, yazın"
        let bubble = labelled(text)
        XCTAssertTrue(bubble.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2.5)
        let quote = element("clomni.composer").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertFalse(quote.exists, "nothing is quoted yet")
        let start = bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 130, dy: 0)), withVelocity: .default,
                    thenHoldForDuration: 0.1)
        let answered = quote.waitForExistence(timeout: 5)
        keep("swiped-to-answer")
        XCTAssertTrue(answered, "the quote stands over the field")
    }

    /// A voice message just sent (the demo's microphone, held for three seconds) stands at the end: a drag down from
    /// its waveform moves the list, and a drag along the waveform moves the playhead (the time under it shows what is
    /// left from there).
    func testOnAVoiceMessageAVerticalDragScrollsAndAHorizontalOneSeeks() {
        launch()
        let mic = element("clomni.composer.voice")
        XCTAssertTrue(mic.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2.5)
        mic.press(forDuration: 3)
        // The waveform reads "Səsli mesaj, 0:03"; the microphone's "Səsli mesaj yaz" is not it.
        let waveform = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "Səsli mesaj, [0-9]+:[0-9]+")).firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 10), "the voice message stands in the conversation")
        let length = waveform.value as? String
        let before = settled(waveform)
        keep("voice-before")

        let start = waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: before.width * 0.6, dy: 0)),
                    withVelocity: .default, thenHoldForDuration: 0.1)
        let seeked = eventually { (waveform.value as? String) != length }
        keep("voice-seeked")
        let along = settled(waveform)
        XCTAssertTrue(seeked, "the time under the waveform \(before) moved from \(length ?? "nil"); then \(along)")
        XCTAssertEqual(along.minY, before.minY, accuracy: 2, "a drag along the waveform did not move the list")

        drag(waveform, dy: 140)
        let after = settled(waveform)
        keep("voice-scrolled")
        XCTAssertGreaterThan(after.minY - before.minY, 80,
                             "a drag down from the waveform \(before) moved the list into the history: \(after)")
    }

    // MARK: - Helpers

    /// A drag from the middle of `element`, `dy` down (up when negative), held at its end so the list does not glide on.
    private func drag(_ element: XCUIElement, dy: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .default,
                    thenHoldForDuration: 0.3)
    }

    /// Whether `condition` holds within 5 s.
    private func eventually(_ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func count(_ text: String) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).count
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
