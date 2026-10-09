import XCTest

/// Home in the messenger's page sheet (`-ClomniDemoHome`, no server). TestFlight 13 (iOS 27) showed ~130 pt of empty
/// brand colour over the logo, the page pulled down past its top.
@MainActor
final class HomeTests: XCTestCase {
    /// The logo's row (✕ is on its line) stands at the top of the sheet, after a short pull down too; a long pull
    /// closes the sheet, as the system's sheets do.
    func testHomeStandsAtTheTopAndAPullDownClosesIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoHome"]
        app.launch()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Bağla", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Home opened")
        let home = app.descendants(matching: .any).matching(identifier: "clomni.home").firstMatch
        let greeting = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Salam")).firstMatch
        keep(app, "home-opened")
        assertAtTheTop(close: settled(close), sheet: settled(home), greeting: settled(greeting), "at the opening")

        // A short, slow pull from the greeting: the page does not move down from its top, and once let go Home is
        // where it was (or the sheet has gone).
        let start = greeting.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)), withVelocity: .slow,
                    thenHoldForDuration: 0.2)
        if close.waitForExistence(timeout: 2) {
            keep(app, "home-after-short-pull")
            assertAtTheTop(close: settled(close), sheet: settled(home), greeting: settled(greeting), "after a short pull")
        }

        // A long pull from the top closes the sheet.
        if close.exists {
            let top = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 500)), withVelocity: .fast,
                      thenHoldForDuration: 0)
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "pulled down from the top, the sheet closes")
    }

    private func assertAtTheTop(close: CGRect, sheet: CGRect, greeting: CGRect, _ when: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(close.minY - sheet.minY, 80, "\(when): the logo's row \(close) is at the sheet's top \(sheet)",
                          file: file, line: line)
        XCTAssertLessThan(greeting.minY - sheet.minY, 200, "\(when): the greeting \(greeting) is under it",
                          file: file, line: line)
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
    private func keep(_ app: XCUIApplication, _ name: String) {
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
