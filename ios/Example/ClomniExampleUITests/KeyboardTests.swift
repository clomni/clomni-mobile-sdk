import UIKit
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
    /// Under the composer's field: ComposerView's vertical padding (Space.s).
    private static let composerBottomPadding: CGFloat = 8

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

    /// TestFlight 13 (iOS 27): after a flow's choice the conversation jumped to its first messages and stayed there, the
    /// next choices out of sight. Here each choice is answered a second later by the next step, its text and three
    /// choices; at every step, once the history has come, the choices stand at the end, on screen, and the first
    /// message is far up, out of sight.
    func testAFlowsNextChoicesStandAtTheEnd() {
        launch(["-ClomniDemoFlow"])
        let window = app.windows.firstMatch
        for step in 1...4 {
            let choice = labelled("Velosiped dayandı \(step)")
            XCTAssertTrue(choice.waitForExistence(timeout: 15), "step \(step)'s choices came")
            let last = labelled("Operatorla danış \(step)")
            let frame = settled(last)
            keep("flow-step-\(step)")
            XCTAssertLessThanOrEqual(frame.maxY, window.frame.maxY, "step \(step): the last choice \(frame) is on screen")
            XCTAssertGreaterThan(frame.minY, window.frame.height / 3, "and low on it, at the end")
            XCTAssertTrue(last.isHittable, "step \(step): the last choice can be tapped")
            let first = labelled("Salam, kartla ödəniş keçmir")
            XCTAssertFalse(first.exists && first.isHittable, "step \(step): the first message is out of sight")
            choice.tap()
        }
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
        // What the user reads: the form above the question. It does not move when the answer comes.
        let reading = element("clomni.form.submit")
        let before = settled(reading)
        let capsule = element("clomni.chat.newMessage")
        XCTAssertTrue(capsule.waitForExistence(timeout: 20), "\"Yeni mesaj\" shows")
        let answer = labelled("Bəli, yoxlayıb")
        XCTAssertFalse(answer.exists && answer.isHittable, "the list stayed where the user reads")
        let after = settled(reading)
        XCTAssertEqual(after.minY, before.minY, accuracy: 1, "what the user reads \(before) stayed where it was: \(after)")
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

    /// The operator's iPhone (2026-10-09, dark mode, the emoji keyboard): a dark band of about 40 pt stood between the
    /// composer and the keyboard. The composer stands right on the keyboard: with the letters, with the emoji keyboard
    /// (its own height, its search field) and back, in the messenger's page sheet.
    func testTheComposerStandsOnEveryKeyboard() {
        launch()
        standsOnEveryKeyboard("sheet")
    }

    /// The same in a full-screen presentation, where the screen reaches the home indicator.
    func testTheComposerStandsOnEveryKeyboardFullScreen() {
        launch(["-ClomniDemoFullScreen"])
        standsOnEveryKeyboard("full-screen")
    }

    private func standsOnEveryKeyboard(_ presentation: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = element("clomni.composer.field")
        XCTAssertTrue(field.waitForExistence(timeout: 15), file: file, line: line)
        // Down: the field at the bottom, over the home indicator (the composer's background reaches under it).
        let down = settled(field)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(down.maxY, window.maxY - 80, "\(presentation): down, the field \(down) is at the bottom",
                             file: file, line: line)
        XCTAssertLessThan(down.maxY, window.maxY - 20, "and over the home indicator", file: file, line: line)

        field.tap()
        onTheKeyboard(field, "\(presentation)-letters", file: file, line: line)
        let switcher = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@",
                                                                  ["Emoji", "Next keyboard", "Next Keyboard"])).firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), "the keyboard's emoji key", file: file, line: line)
        switcher.tap()
        onTheKeyboard(field, "\(presentation)-emoji", file: file, line: line)
        let letters = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["ABC", "Next keyboard",
                                                                                          "Next Keyboard"])).firstMatch
        XCTAssertTrue(letters.waitForExistence(timeout: 5), "the emoji keyboard's way back", file: file, line: line)
        letters.tap()
        onTheKeyboard(field, "\(presentation)-letters-again", file: file, line: line)
        // Typed text changes the suggestions over the letters, not where the composer stands.
        field.typeText("Salam")
        onTheKeyboard(field, "\(presentation)-typing", file: file, line: line)
    }

    /// The composer on the keyboard's top, read from the screen's pixels: under the field's grey only the composer's
    /// own padding of white, then the keyboard; no band of the page between them, and no keyboard over the field.
    /// (XCUITest's keyboard frame leaves out the suggestions over the letters, and the composer's frame reaches under
    /// the home indicator while it is down.)
    private func onTheKeyboard(_ field: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        _ = settledKeyboard(file: file, line: line)
        let frame = settled(field)
        let screenshot = app.screenshot()
        keep(name)
        let white = whiteUnder(frame, in: screenshot.image)
        XCTAssertEqual(white, Self.composerBottomPadding, accuracy: 1.5,
                       "\(name): \(white) pt of white between the field \(frame) and the keyboard, its padding alone",
                       file: file, line: line)
    }

    /// How much white is under the field's grey background before something else (the keyboard) begins, in points:
    /// read down the screenshot from just under the field's text. 0 when the field's grey runs into the keyboard.
    private func whiteUnder(_ field: CGRect, in image: UIImage) -> CGFloat {
        guard let picture = image.cgImage else { return -1 }
        let width = picture.width, height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        let scale = CGFloat(width) / image.size.width
        let x = Int(field.midX * scale)
        func isWhite(_ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            return bytes[offset] > 250 && bytes[offset + 1] > 250 && bytes[offset + 2] > 250
        }
        // The field's grey goes on at most 20 pt under its text; where it ends the white starts, or the keyboard.
        var y = Int((field.maxY + 1) * scale)
        let greyEnds = min(height, Int((field.maxY + 20) * scale))
        while y < greyEnds, !isWhite(y) { y += 1 }
        guard y < greyEnds else { return 0 }
        let start = y
        while y < height, isWhite(y) { y += 1 }
        return CGFloat(y - start) / scale
    }

    /// CM-087 (the RN test on Android): a picked file opens its strip over the composer; the end of the conversation
    /// comes into sight over it, also when the user was reading further up. The demo picks a picture ten seconds
    /// after "Şəkil göndərirəm", as the photo library would hand it over.
    func testAPickedFileBringsTheEndIntoSightOverItsStrip() {
        launch()
        let composer = element("clomni.composer.field")
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        _ = settledKeyboard()
        composer.typeText("Şəkil göndərirəm")
        element("clomni.composer.send").tap()
        let sent = labelled("Şəkil göndərirəm")
        XCTAssertTrue(sent.waitForExistence(timeout: 3))
        // Back into the history, well past what still counts as the end, the drag over and held.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 350)), withVelocity: .default,
                    thenHoldForDuration: 0.3)
        keep("reading-above-before-the-file")

        let picked = labelled("image.jpg")
        XCTAssertTrue(picked.waitForExistence(timeout: 15), "the picture's strip over the composer")
        let bubble = settled(sent)
        let strip = settled(picked)
        let field = settled(composer)
        keep("file-picked")
        XCTAssertLessThanOrEqual(strip.maxY, field.minY, "the strip \(strip) is over the field \(field)")
        onTheKeyboard(composer, "file-picked-on-the-keyboard")
        XCTAssertLessThan(bubble.maxY, strip.minY, "the last message \(bubble) is over the strip \(strip)")
        XCTAssertGreaterThan(bubble.minY, 0)
        XCTAssertEqual(settled(element("clomni.composer")).minY - bubble.maxY, Self.listBottomPadding, accuracy: 2,
                       "at the list's very end")
    }

    /// CM-087 (the RN test on Android, where TalkBack read the last bot message twice): a message is one element for
    /// VoiceOver, the last of the bot's and of the operator's too, and a step that comes after a choice.
    func testTheLastMessagesAreOneElementEach() {
        launch(["-ClomniDemoFlow"])
        XCTAssertTrue(labelled("Nə baş verib? (1)").waitForExistence(timeout: 15))
        keep("one-element-each")
        XCTAssertEqual(count("Nə baş verib? (1)"), 1, "the bot's last message")
        XCTAssertEqual(count("Başqa sualınız olsa, yazın"), 1, "the operator's last message")
        labelled("Velosiped dayandı 1").tap()
        XCTAssertTrue(labelled("Nə baş verib? (2)").waitForExistence(timeout: 10))
        XCTAssertEqual(count("Nə baş verib? (2)"), 1, "the next step")
        XCTAssertEqual(count("Velosiped dayandı 1"), 1, "the choice, now the user's message")
    }

    /// How many elements VoiceOver has whose words contain `text`.
    private func count(_ text: String) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).count
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
