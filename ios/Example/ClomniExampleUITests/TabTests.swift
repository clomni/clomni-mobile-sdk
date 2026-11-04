import UIKit
import XCTest

/// The tab bar (SDK 1.0.7) in the messenger's page sheet, through the messenger's own coordinator and navigation
/// (`-ClomniDemoTabs`, no server): Home, the conversations with 7 unread, the news and the FAQ.
@MainActor
final class TabTests: XCTestCase {
    /// TestFlight #19 (iPhone, iOS 18, CM-346): back on Home from another tab, a frame of blank white sheet, then Home
    /// all at once; Home was built again each time. The tabs stay as they were: Home is there the moment its tab is
    /// tapped, scrolled where it was left.
    func testHomeIsThereAtOnceWhenItsTabComesBack() throws {
        continueAfterFailure = false
        let app = launch()
        let greeting = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Salam")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 20), "Home opened")
        let home = tab(app, "home"), messages = tab(app, "messages")
        XCTAssertTrue(messages.waitForExistence(timeout: 5), "with the tab bar")
        let opened = settled(greeting)
        keep(app, "tabs-home")

        // To the conversations and back: no blank white sheet (#FFFFFF; the conversations' page is #F5F6F8, Home's
        // header the brand's blue) where the greeting is.
        showConversations(app, messages)
        home.tap()
        let back = app.screenshot()
        XCTAssertTrue(greeting.exists, "Home is there at once, not after a blank frame")
        let behind = try XCTUnwrap(Pixels(back)).rgb(CGPoint(x: opened.minX - 8, y: opened.midY))
        XCTAssertFalse(behind.r >= 252 && behind.g >= 252 && behind.b >= 252, "a blank white sheet: \(behind)")
        keep(app, "tabs-home-again")

        // Scrolled down a little, Home is still scrolled there after another tab.
        let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -160)), withVelocity: .slow,
                   thenHoldForDuration: 0.3)
        let scrolled = settled(greeting)
        XCTAssertLessThan(scrolled.minY, opened.minY - 60, "Home scrolled: \(opened) → \(scrolled)")
        showConversations(app, messages)
        home.tap()
        XCTAssertTrue(greeting.exists, "Home is there at once")
        XCTAssertEqual(greeting.frame.minY, scrolled.minY, accuracy: 2, "Home where it was left, not built again at its top")
        keep(app, "tabs-home-scrolled")
    }

    /// The unread count on the conversations' tab (operator, 2026-11-04: it had "burst", big and over the icon): 16 pt
    /// high, at least a circle, its left edge about 4 pt right of the icon's centre, inside its tab; VoiceOver reads it.
    func testTheUnreadCountSitsOnTheIcon() throws {
        continueAfterFailure = false
        let app = launch()
        let messages = tab(app, "messages")
        XCTAssertTrue(messages.waitForExistence(timeout: 20), "the tab bar")
        XCTAssertTrue(messages.label.contains("7"), "VoiceOver reads the count: \(messages.label)")
        let frame = settled(messages)
        let shot = app.screenshot()
        keep(app, "tabs-badge")
        // The unread red (#E5484D) in the tab and the band over it, where a badge that sticks out would be.
        let area = CGRect(x: frame.minX, y: frame.minY - 8, width: frame.width, height: frame.height + 8)
        let badge = try XCTUnwrap(Pixels(shot)?.bounds(in: area) { $0 > 180 && $1 < 120 && $2 < 120 }, "a red badge")
        XCTAssertTrue(frame.insetBy(dx: -0.5, dy: -0.5).contains(badge), "the badge \(badge) inside its tab \(frame)")
        XCTAssertEqual(badge.height, 16, accuracy: 1.5, "16 pt high: \(badge)")
        XCTAssertGreaterThanOrEqual(badge.width, badge.height - 1, "at least a circle: \(badge)")
        XCTAssertEqual(badge.minX - frame.midX, 4, accuracy: 2, "its left edge ~4 pt right of the icon's centre: \(badge)")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoTabs"]
        app.launch()
        return app
    }

    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "clomni.tab.\(name)").firstMatch
    }

    /// The conversations' tab, until its list shows.
    private func showConversations(_ app: XCUIApplication, _ messages: XCUIElement) {
        messages.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Tarif dəyişdi")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the conversations")
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

/// A screenshot's pixels, read in points from the top left.
private struct Pixels {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let data: [UInt8]

    init?(_ screenshot: XCUIScreenshot) {
        let image = screenshot.image
        guard let cgImage = image.cgImage, image.size.width > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        width = cgImage.width
        height = cgImage.height
        scale = CGFloat(cgImage.width) / image.size.width
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        data = buffer
    }

    func rgb(_ point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let x = min(width - 1, max(0, Int(point.x * scale))), y = min(height - 1, max(0, Int(point.y * scale)))
        let index = (y * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// The bounds, in points, of the pixels in `rect` whose colour matches; nil when none does.
    func bounds(in rect: CGRect, where matches: (Int, Int, Int) -> Bool) -> CGRect? {
        let minX = max(0, Int(rect.minX * scale)), maxX = min(width - 1, Int(rect.maxX * scale))
        let minY = max(0, Int(rect.minY * scale)), maxY = min(height - 1, Int(rect.maxY * scale))
        guard minX <= maxX, minY <= maxY else { return nil }
        var found: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in minY...maxY {
            for x in minX...maxX {
                let index = (y * width + x) * 4
                guard matches(Int(data[index]), Int(data[index + 1]), Int(data[index + 2])) else { continue }
                found = (min(found?.minX ?? x, x), min(found?.minY ?? y, y), max(found?.maxX ?? x, x), max(found?.maxY ?? y, y))
            }
        }
        guard let found else { return nil }
        return CGRect(x: CGFloat(found.minX) / scale, y: CGFloat(found.minY) / scale,
                      width: CGFloat(found.maxX - found.minX + 1) / scale, height: CGFloat(found.maxY - found.minY + 1) / scale)
    }
}
