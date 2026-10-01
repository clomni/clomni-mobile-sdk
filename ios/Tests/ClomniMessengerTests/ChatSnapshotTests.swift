// Snapshots need UIKit: they run on the iOS Simulator (CI's xcodebuild test step), not in swift test on Linux or macOS.
#if canImport(UIKit) && canImport(SwiftUI)
import Foundation
import SwiftUI
import UIKit
import XCTest
import ClomniProtocol
import ClomniPresentation
@testable import ClomniMessenger

/// Every message fixture of protocol/fixtures/index.json in the conversation screen, light and dark, compared with its
/// reference picture in `__Snapshots__` next to this file.
///
/// How the references come about: a run that finds no reference for a picture writes it there and passes, saying
/// "recorded" in the log. CI uploads the folder as the `snapshots` artifact after every run; download it once, look
/// the pictures over against docs/ui-reference.html (section 4) and commit them under
/// ios/Tests/ClomniMessengerTests/__Snapshots__. From then on a picture that changes fails the test and is written
/// next to its reference as `<name>.failed.png`. To accept a deliberate change, delete the reference or run with
/// CLOMNI_RECORD_SNAPSHOTS=1.
@MainActor
final class ChatSnapshotTests: XCTestCase {
    /// 2026-10-01T10:32:00Z, two minutes after most fixtures.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures")
    }

    func testEveryMessageFixture() throws {
        let index = try JSONDecoder().decode([[String: JSONValue]].self,
                                             from: Data(contentsOf: fixtures.appendingPathComponent("index.json")))
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(Data(contentsOf: fixtures.appendingPathComponent("42-config-apar.json"))))
        var rendered = 0
        for entry in index where entry["schema"]?.stringValue == "message.json" {
            let file = try XCTUnwrap(entry["file"]?.stringValue)
            // A message the parser drops (no seq, say) has nothing to show.
            guard let message = ProtocolJSON.parseMessage(try Data(contentsOf: fixtures.appendingPathComponent(file)))
            else { continue }
            var snapshot = ChatSnapshot(config: config, messages: [message])
            snapshot.answerable = message.flow?.interactive == true ? [message.id] : []
            snapshot.load = .loaded
            let screen = ChatPresenter(strings: ClomniStrings(language: "az", overrides: config.strings),
                                       timeZone: TimeZone(identifier: "UTC")!, now: now).screen(snapshot)
            for dark in [false, true] {
                let theme = ClomniTheme.make(brand: config.brand, dark: dark)
                let image = Snapshot.render(SnapshotScene(screen: screen, theme: theme), width: 390, dark: dark)
                try Snapshot.assert(image, named: (file as NSString).deletingPathExtension + (dark ? "-dark" : "-light"))
            }
            rendered += 1
        }
        XCTAssertGreaterThanOrEqual(rendered, 35)
    }
}

/// Header, transcript and composer without scrolling, so the picture holds the whole conversation.
private struct SnapshotScene: View {
    let screen: ChatScreen
    let theme: ClomniTheme

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(header: screen.header, theme: theme, back: {}, close: {})
            ChatTranscript(items: screen.items, theme: theme, actions: ChatActions())
            ComposerView(composer: screen.composer, theme: theme, text: .constant(""), writeAnyway: .constant(false),
                         send: {}, attach: {}, startNew: {})
        }
        .background(theme.colors.background.color)
        .environment(\.clomniLoadsRemoteImages, false)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .dynamicTypeSize(.large)
    }
}

/// Renders SwiftUI through UIKit (so text fields and pickers draw too) and compares pictures.
enum Snapshot {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")

    @MainActor
    static func render<Content: View>(_ view: Content, width: CGFloat, dark: Bool) -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = dark ? .dark : .light
        let fitting = controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: width, height: max(1, fitting.height.rounded(.up)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    static func assert(_ image: UIImage, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let png = image.pngData() else { return XCTFail("\(name): no PNG", file: file, line: line) }
        let reference = directory.appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["CLOMNI_RECORD_SNAPSHOTS"] == "1"
            || !FileManager.default.fileExists(atPath: reference.path) {
            try png.write(to: reference)
            print("snapshot recorded: \(reference.path)")
            return
        }
        guard let expected = UIImage(contentsOfFile: reference.path), matches(image, expected) else {
            try png.write(to: directory.appendingPathComponent("\(name).failed.png"))
            return XCTFail("\(name) no longer looks like its reference; the new picture is \(name).failed.png",
                           file: file, line: line)
        }
    }

    /// The same size, and at most 0.5% of the pixels off by more than a little: antialiasing varies between runs.
    static func matches(_ actual: UIImage, _ expected: UIImage) -> Bool {
        guard let left = pixels(actual), let right = pixels(expected), left.width == right.width,
              left.height == right.height else { return false }
        var differing = 0
        for offset in stride(from: 0, to: left.bytes.count, by: 4) {
            for channel in 0..<4 where abs(Int(left.bytes[offset + channel]) - Int(right.bytes[offset + channel])) > 8 {
                differing += 1
                break
            }
        }
        return Double(differing) <= 0.005 * Double(left.width * left.height)
    }

    private static func pixels(_ image: UIImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (width, height, bytes) : nil
    }
}
#endif
