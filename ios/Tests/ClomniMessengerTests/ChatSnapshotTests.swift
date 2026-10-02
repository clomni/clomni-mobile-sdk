// Snapshots need UIKit: they run on the iOS Simulator (CI's xcodebuild test step), not in swift test on Linux or macOS.
#if canImport(UIKit) && canImport(SwiftUI)
import Foundation
import SwiftUI
import UIKit
import XCTest
import ClomniProtocol
import ClomniPresentation
@testable import ClomniMessenger

/// Every message fixture of protocol/fixtures/index.json in the conversation screen, and Home, light and dark, at the
/// default text size and at accessibility3, compared with their reference pictures in `__Snapshots__` next to this
/// file.
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

    /// The renderer draws what it is given, and a blank picture is told apart: without this every snapshot was
    /// recorded white and still passed.
    func testTheRendererDraws() {
        let text = Snapshot.render(Text("Salam").font(.title).padding(20).background(Color.white), width: 200, dark: false)
        XCTAssertFalse(Snapshot.isBlank(text), "text on white is drawn")
        let solid = Snapshot.render(Color.white.frame(width: 50, height: 50), width: 50, height: 50, dark: false)
        XCTAssertTrue(Snapshot.isBlank(solid), "one colour is blank")
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
            for variant in Variant.all {
                let theme = ClomniTheme.make(brand: config.brand, dark: variant.dark)
                let image = Snapshot.render(SnapshotScene(screen: screen, theme: theme, size: variant.size), width: 390,
                                            dark: variant.dark)
                try Snapshot.assert(image, named: (file as NSString).deletingPathExtension + variant.suffix)
            }
            rendered += 1
        }
        XCTAssertGreaterThanOrEqual(rendered, 35)
    }

    /// Home as the brief draws it, while it loads, and when getting ready failed ("Yenidən cəhd et").
    func testHome() throws {
        let screens: [(String, HomeScreen)] = [
            ("home", PreviewData.presenter.home(PreviewData.snapshot())),
            ("home-loading", PreviewData.presenter.preparing(failed: false)),
            ("home-failed", PreviewData.presenter.preparing(failed: true)),
        ]
        for (name, screen) in screens {
            for variant in Variant.all {
                // Before the config arrives the messenger draws in the neutral theme, as MessengerRootView does.
                let theme = name == "home" ? PreviewData.theme(dark: variant.dark)
                    : ClomniTheme.make(config: nil, systemIsDark: variant.dark)
                let view = HomeView(screen: screen, theme: theme, actions: MessengerActions())
                    .environment(\.clomniLoadsRemoteImages, false)
                    .environment(\.colorScheme, variant.dark ? .dark : .light)
                    .dynamicTypeSize(variant.size)
                let image = Snapshot.render(view, width: 390, height: 844, dark: variant.dark)
                // The header's colour runs up under the status bar: the top row is the header's, not the page's.
                let top = Snapshot.pixel(image, x: 4, y: 4) ?? []
                let header = Snapshot.rgb(theme.colors.headerFrom)
                XCTAssertTrue(top.count == 3 && zip(top, header).allSatisfy { abs($0 - $1) <= 6 },
                              "\(name + variant.suffix): the status bar's strip is \(top), the header \(header)")
                try Snapshot.assert(image, named: name + variant.suffix)
            }
        }
    }
}

/// Light and dark, at the default text size and at accessibility3 (Dynamic Type past 200%, DoD 11).
private struct Variant {
    let dark: Bool
    let size: DynamicTypeSize

    var suffix: String {
        (dark ? "-dark" : "-light") + (size == .large ? "" : "-ax3")
    }

    static let all = [Variant(dark: false, size: .large), Variant(dark: true, size: .large),
                      Variant(dark: false, size: .accessibility3), Variant(dark: true, size: .accessibility3)]
}

/// Header, transcript and composer without scrolling, so the picture holds the whole conversation.
private struct SnapshotScene: View {
    let screen: ChatScreen
    let theme: ClomniTheme
    let size: DynamicTypeSize

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
        .dynamicTypeSize(size)
    }
}

/// Renders SwiftUI through UIKit (so text fields and pickers draw too) and compares pictures.
enum Snapshot {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")

    /// `height`: a screen's (a view that scrolls has no height of its own); nil fits the content.
    @MainActor
    static func render<Content: View>(_ view: Content, width: CGFloat, height: CGFloat? = nil, dark: Bool) -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = dark ? .dark : .light
        let fitting = controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: width, height: height ?? max(1, fitting.height.rounded(.up)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // SwiftUI commits its drawing on the run loop; give it a turn, then flush the layer tree.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutIfNeeded()
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        // The layer tree itself: drawHierarchy needs a window on screen, which a package's test run (no app, no
        // scene) does not have, and drew every snapshot blank.
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        return image
    }

    static func assert(_ image: UIImage, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let png = image.pngData() else { return XCTFail("\(name): no PNG", file: file, line: line) }
        // A picture of one colour is a render that drew nothing, not a screen: never a reference.
        guard !isBlank(image) else {
            return XCTFail("\(name): the picture is one colour; nothing was drawn", file: file, line: line)
        }
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

    /// One pixel (at the picture's scale), red, green, blue; nil outside it.
    static func pixel(_ image: UIImage, x: Int, y: Int) -> [Int]? {
        guard let picture = pixels(image), x < picture.width, y < picture.height else { return nil }
        let offset = (y * picture.width + x) * 4
        return picture.bytes[offset..<offset + 3].map(Int.init)
    }

    static func rgb(_ color: RGBColor) -> [Int] {
        [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
    }

    /// Every pixel the same (or no pixels at all).
    static func isBlank(_ image: UIImage) -> Bool {
        guard let picture = pixels(image), picture.bytes.count >= 4 else { return true }
        let first = picture.bytes[0..<4]
        return stride(from: 4, to: picture.bytes.count, by: 4).allSatisfy { picture.bytes[$0..<$0 + 4] == first }
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
