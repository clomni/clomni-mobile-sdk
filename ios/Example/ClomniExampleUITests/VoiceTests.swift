import UIKit
import XCTest

/// CM-130 on a simulator: with the field empty the composer's round button is the microphone; held for a second and a
/// half and let go, the recording (the demo's microphone double: a UI test cannot rely on the simulator's) goes to the
/// outbox as a voice message and stands in the conversation as a voice bubble with its clock.
@MainActor
final class VoiceTests: XCTestCase {
    private var app: XCUIApplication!

    func testHoldingTheMicrophoneSendsAVoiceMessage() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"]
        app.launch()
        let mic = app.descendants(matching: .any).matching(identifier: "clomni.composer.voice").firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 15), "the microphone is the composer's round button")
        keep("voice-composer-empty")
        mic.press(forDuration: 1.6)
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Səsli mesaj")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "the voice message stands in the conversation")
        keep("voice-sent")
        // Text in the field turns the microphone into the arrow.
        let field = app.descendants(matching: .any).matching(identifier: "clomni.composer.field").firstMatch
        field.tap()
        field.typeText("Salam")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "clomni.composer.send").firstMatch.waitForExistence(timeout: 5))
    }

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
