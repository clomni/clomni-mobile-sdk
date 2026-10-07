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
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(close(app).waitForExistence(timeout: 20), "opened again from the background")

        // From the background, the messenger open: it moves to the push's conversation.
        XCUIDevice.shared.press(.home)
        app.activate()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.state, .runningForeground, "still running after a tap with the messenger open")
        XCTAssertTrue(close(app).exists)
    }

    /// The messenger's ✕, in whichever language it speaks.
    private func close(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Bağla", "Close", "Закрыть"])).firstMatch
    }
}
