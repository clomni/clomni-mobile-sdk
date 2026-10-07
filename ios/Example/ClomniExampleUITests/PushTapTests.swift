import XCTest

/// A tap on a Clomni notification opens the messenger and the app keeps running: at a cold start, and from the
/// background with the messenger closed and open. The app taps for itself (`-ClomniPushTap`, UITestPushTap in the
/// Example) the way UIKit does: from a background queue, with a completion handler that must be called on the main
/// thread. TestFlight build 8 stopped right there: the delegate method was nonisolated, so Swift called UIKit's
/// handler from a background thread.
@MainActor
final class PushTapTests: XCTestCase {
    func testATapOnANotificationOpensTheMessenger() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // No account here: "conv_test" stays a conversation that cannot load; with one the server's 404 opens Home.
        app.launchArguments += ["-ClomniPushTap", "conv_test,conv_5521,conv_7"]
        app.launch()

        // Cold start: the tap comes before the app's window is up.
        XCTAssertTrue(close(app).waitForExistence(timeout: 20), "the messenger opened from the tap at launch")
        XCTAssertEqual(app.state, .runningForeground)

        // From the background, the messenger closed.
        close(app).tap()
        XCTAssertTrue(close(app).waitForNonExistence(timeout: 5))
        goHomeAndBack(app)
        XCTAssertTrue(close(app).waitForExistence(timeout: 20), "opened again from the background")

        // From the background, the messenger open: it moves to the push's conversation.
        goHomeAndBack(app)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.state, .runningForeground, "still running after a tap with the messenger open")
        XCTAssertTrue(close(app).exists)
    }

    /// To the home screen and back, each step finished before the next. On CI (f92fc22) the app was found in the
    /// background 3 s after an activation sent 0.5 s after the press, before the app had left the foreground: state 3,
    /// alive, not a crash, and the same steps had passed on the run before.
    private func goHomeAndBack(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.press(.home)
        let deadline = Date().addingTimeInterval(10)
        while app.state == .runningForeground, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertNotEqual(app.state, .runningForeground, "the app went to the background", file: file, line: line)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "and came back", file: file, line: line)
    }

    /// The messenger's ✕, in whichever language it speaks.
    private func close(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Bağla", "Close", "Закрыть"])).firstMatch
    }
}
