import XCTest

/// SDK 1.0.7 on a simulator: the user deletes their own message from its long-press menu, after a question; the bubble
/// becomes "Bu mesaj silindi", and a deleted message has no menu at all. The operator's message has no "Sil".
@MainActor
final class DeleteTests: XCTestCase {
    private var app: XCUIApplication!

    func testTheUserDeletesTheirOwnMessage() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoConversation"]
        app.launch()
        let mine = labelled("Çox sağ olun")
        XCTAssertTrue(mine.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2.5)

        // The operator's message: answer and copy, no delete.
        labelled("Başqa sualınız olsa, yazın").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Kopyala"].waitForExistence(timeout: 5), "the operator's menu")
        keep("operator-menu")
        XCTAssertFalse(app.buttons["Sil"].exists, "not the user's to delete")
        app.buttons["Kopyala"].tap()

        mine.press(forDuration: 1.2)
        let delete = app.buttons["Sil"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the user's menu has Sil")
        keep("user-menu")
        delete.tap()
        let alert = app.alerts["Mesaj silinsin?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "it asks first")
        XCTAssertTrue(alert.staticTexts["Mesaj hər kəs üçün silinəcək."].exists)
        keep("delete-confirm")
        alert.buttons["Sil"].tap()

        let deleted = labelled("Bu mesaj silindi")
        XCTAssertTrue(deleted.waitForExistence(timeout: 5), "the bubble says it was deleted")
        XCTAssertFalse(labelled("Çox sağ olun").exists, "nothing of the text is left")
        keep("deleted")

        // Nothing to do with it.
        deleted.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.buttons["Sil"].exists || app.buttons["Cavabla"].exists || app.buttons["Kopyala"].exists,
                       "a deleted message has no menu")
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
