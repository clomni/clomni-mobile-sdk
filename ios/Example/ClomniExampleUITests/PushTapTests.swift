import XCTest

/// A tap on a Clomni notification opens the messenger and the app keeps running: at a cold start, then with the
/// messenger closed and with it open. The app taps for itself (`-ClomniPushTap`, UITestPushTap in the
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

        // The messenger closed: the next tap, 12 s after the first, opens it again.
        close(app).tap()
        XCTAssertTrue(close(app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(close(app).waitForExistence(timeout: 25), "opened again by the next tap")

        // The messenger open: the third tap moves it to that conversation, and the app keeps running.
        Thread.sleep(forTimeInterval: 15)
        XCTAssertEqual(app.state, .runningForeground, "still running after a tap with the messenger open")
        XCTAssertTrue(close(app).exists)
    }

    /// The messenger's ✕, in whichever language it speaks.
    private func close(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Bağla", "Close", "Закрыть"])).firstMatch
    }
}
