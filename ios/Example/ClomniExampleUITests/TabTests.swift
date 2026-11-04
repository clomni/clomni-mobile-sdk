import UIKit
import XCTest

/// The tab bar (SDK 1.0.7) in the messenger's page sheet, through the messenger's own coordinator and navigation
/// (`-ClomniDemoTabs`, no server): Home, the conversations with 7 unread, the news and the FAQ.
@MainActor
final class TabTests: XCTestCase {
    /// TestFlight #21 (CM-346 § 5.1): the operator wants no cross-fade, where the old screen and the new one showed
    /// through each other, but the new screen's own background with the spinner in its middle, then its content. The
    /// spinner is held for 1.5 s here (`-ClomniDemoEntrySeconds`, 0.35 s in the app) so the test sees it. A tab keeps
    /// its place: back on Home after the spinner, it is scrolled where it was left. A pushed screen (a news item)
    /// opens the same way.
    func testANewScreenShowsTheSpinnerAloneThenItsContent() throws {
        continueAfterFailure = false
        let app = launch(["-ClomniDemoEntrySeconds", "1.5"])
        let greeting = labelled(app, "Salam")
        XCTAssertTrue(greeting.waitForExistence(timeout: 20), "Home opened")
        let home = tab(app, "home"), messages = tab(app, "messages")
        XCTAssertTrue(messages.waitForExistence(timeout: 5), "with the tab bar")
        let opened = settled(greeting)
        keep(app, "entry-home")

        // Scrolled down a little first, to see it kept.
        let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -160)), withVelocity: .slow,
                   thenHoldForDuration: 0.3)
        let scrolled = settled(greeting)
        XCTAssertLessThan(scrolled.minY, opened.minY - 60, "Home scrolled: \(opened) → \(scrolled)")

        let row = labelled(app, "Tarif dəyişdi")
        messages.tap()
        try assertSpinnerAlone(app, gone: [greeting, row], "the conversations' tab")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "then the conversations")
        XCTAssertFalse(spinner(app).exists, "and the spinner is gone")
        keep(app, "entry-messages")

        home.tap()
        try assertSpinnerAlone(app, gone: [greeting, row], "Home's tab")
        XCTAssertTrue(greeting.waitForExistence(timeout: 5), "then Home")
        XCTAssertEqual(settled(greeting).minY, scrolled.minY, accuracy: 2, "Home where it was left, not built again")

        // A push: a news item from Home's card.
        let item = labelled(app, "Bayram iş saatları")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let body = labelled(app, "9 noyabrda dəstək")
        try assertSpinnerAlone(app, gone: [greeting, body], "a news item")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "then the news item")
        keep(app, "entry-news")
    }

    /// Right after a tap: the spinner in the middle of the new screen, nothing of the screen left nor of the one coming
    /// (`gone`), and around the spinner the page's own colour only, so two screens never show through each other.
    private func assertSpinnerAlone(_ app: XCUIApplication, gone: [XCUIElement], _ what: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let shot = app.screenshot()
        let loading = spinner(app)
        XCTAssertTrue(loading.exists, "\(what): the spinner first", file: file, line: line)
        for element in gone {
            XCTAssertFalse(element.exists, "\(what): no content yet, of either screen", file: file, line: line)
        }
        let window = app.windows.firstMatch.frame
        let centre = loading.frame
        XCTAssertEqual(centre.midX, window.midX, accuracy: 2, "\(what): in the middle", file: file, line: line)
        keep(shot, "entry-spinner")
        // Between the screen's bar and the tab bar (or the bottom), away from the spinner: one colour.
        let bottom = tab(app, "home").exists ? tab(app, "home").frame.minY - 4 : window.maxY - 40
        let area = CGRect(x: window.minX + 16, y: window.minY + window.height * 0.22, width: window.width - 32,
                          height: bottom - (window.minY + window.height * 0.22))
        let pixels = try XCTUnwrap(Pixels(shot))
        let page = pixels.rgb(CGPoint(x: area.minX + 2, y: area.minY + 2))
        let around = centre.insetBy(dx: -24, dy: -24)
        let other = pixels.bounds(in: area) { r, g, b in
            abs(r - page.r) > 12 || abs(g - page.g) > 12 || abs(b - page.b) > 12
        }
        XCTAssertTrue(other.map { around.contains($0) } ?? true,
                      "\(what): only the spinner \(centre) on the page \(page), found \(other.map { "\($0)" } ?? "")",
                      file: file, line: line)
    }

    /// The unread count on the conversations' tab (operator, 2026-11-04: it had "burst"; TestFlight #21: its top under
    /// the bar's line): 16 pt high, at least a circle, its left edge about 4 pt right of the icon's centre, its middle
    /// near the icon's top edge, and at least 4 pt under the bar's top line; VoiceOver reads it. Light and dark.
    func testTheUnreadCountSitsInsideTheTabBarLight() throws {
        try checkTheBadge(dark: false)
    }

    func testTheUnreadCountSitsInsideTheTabBarDark() throws {
        try checkTheBadge(dark: true)
    }

    private func checkTheBadge(dark: Bool) throws {
        continueAfterFailure = false
        let app = launch(dark ? ["-ClomniDemoDark"] : [])
        let messages = tab(app, "messages")
        XCTAssertTrue(messages.waitForExistence(timeout: 20), "the tab bar")
        XCTAssertTrue(messages.label.contains("7"), "VoiceOver reads the count: \(messages.label)")
        // The tab's frame starts at the bar's top line.
        let frame = settled(messages)
        let pixels = try XCTUnwrap(Pixels(app.screenshot()))
        keep(app, dark ? "tabs-badge-dark" : "tabs-badge")
        // The unread red (#E5484D) in the tab and the band over it, where a badge that sticks out would be.
        let area = CGRect(x: frame.minX, y: frame.minY - 8, width: frame.width, height: frame.height + 8)
        let badge = try XCTUnwrap(pixels.bounds(in: area) { $0 > 180 && $1 < 120 && $2 < 120 }, "a red badge")
        // The icon: the grey of a tab not chosen (#707480 light, #9A9DA6 dark), above the label.
        let top = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 36)
        let icon = try XCTUnwrap(pixels.bounds(in: top) { r, g, b in
            (90...200).contains(max(r, g, b)) && max(r, g, b) - min(r, g, b) < 40
        }, "the icon")
        continueAfterFailure = true
        XCTAssertGreaterThanOrEqual(badge.minY - frame.minY, 4, "4 pt under the bar's line: \(badge), bar from \(frame.minY)")
        XCTAssertTrue(frame.contains(badge), "the badge \(badge) inside its tab \(frame)")
        XCTAssertEqual(badge.height, 16, accuracy: 1.5, "16 pt high, nothing cut off: \(badge)")
        XCTAssertGreaterThanOrEqual(badge.width, badge.height - 1, "at least a circle: \(badge)")
        XCTAssertEqual(badge.minX - icon.midX, 4, accuracy: 2, "its left edge ~4 pt right of the icon's centre: \(badge), \(icon)")
        XCTAssertTrue((icon.minY - 3...icon.minY + 6).contains(badge.midY), "its middle by the icon's top edge: \(badge), \(icon)")
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ClomniDemoTabs"] + arguments
        app.launch()
        return app
    }

    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "clomni.tab.\(name)").firstMatch
    }

    private func spinner(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "clomni.loading").firstMatch
    }

    private func labelled(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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

    private func keep(_ app: XCUIApplication, _ name: String) {
        keep(app.screenshot(), name)
    }

    /// As KeyboardTests keeps them: in the result bundle, and in CLOMNI_SCREENSHOTS when it is set.
    private func keep(_ screenshot: XCUIScreenshot, _ name: String) {
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

    @MainActor
    init?(_ screenshot: XCUIScreenshot) {
        let image = screenshot.image
        guard let cgImage = image.cgImage, image.size.width > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (cgImage.width, cgImage.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        scale = CGFloat(width) / image.size.width
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
