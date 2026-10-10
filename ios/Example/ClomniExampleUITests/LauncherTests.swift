import XCTest

/// The launcher at a cold start (CM-087, the RN test on Android): the app turns it on where it initializes the SDK,
/// before its scene and window are up (`-ClomniDemoLauncher`, no server). It shows once they are, and opens Home.
@MainActor
final class LauncherTests: XCTestCase {
    func testTheLauncherShowsWhenTheSDKStartsBeforeTheWindow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoLauncher"]
        app.launch()
        let launcher = app.buttons["clomni.launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 15), "the launcher shows")
        keep(app, "launcher-at-cold-start")
        XCTAssertTrue(launcher.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(launcher.frame.minY, window.height / 2, "at the bottom of the screen")
        XCTAssertGreaterThan(launcher.frame.minX, window.width / 2, "on the right")
        XCTAssertLessThanOrEqual(launcher.frame.maxY, window.maxY, "over the home indicator, not under the screen")

        launcher.tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Bağla", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "a tap opens the messenger")
        keep(app, "launcher-opened-home")
        XCTAssertFalse(launcher.exists, "and the launcher steps aside while it is open")
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
