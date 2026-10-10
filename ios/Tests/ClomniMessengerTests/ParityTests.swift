// UIKit and SwiftUI: on the iOS Simulator (CI's xcodebuild test step), not in swift test on Linux or macOS.
#if canImport(UIKit) && canImport(SwiftUI)
import Foundation
import SwiftUI
import UIKit
import XCTest
import ClomniProtocol
@testable import ClomniPresentation
@testable import ClomniMessenger

/// What the React Native test on Android found (CM-087), checked on iOS where it is drawn.
@MainActor
final class ParityTests: XCTestCase {
    /// A picture with nothing in it, as a logo's transparent parts are.
    private static let transparent = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return format
    }()).image { _ in }

    /// The avatar on white, 10 pt around it; kept in __Snapshots__ (CI's "snapshots" artifact) to be looked at.
    private func render<Avatar: View>(_ avatar: Avatar, size: Double, _ name: String) -> UIImage {
        let image = Snapshot.render(avatar.padding(10).background(Color.white), width: CGFloat(size + 20), dark: false)
        try? FileManager.default.createDirectory(at: Snapshot.directory, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: Snapshot.directory.appendingPathComponent("parity-\(name).png"))
        return image
    }

    /// The panel's logo with transparent parts: the bot's avatar (in the header and next to its messages) and the
    /// "Ən son mesaj" row show it on what is behind it, white here. It showed a grey disc and the initial through it.
    func testALogoWithTransparentPartsShowsNoDiscBehindIt() throws {
        let theme = PreviewData.theme(dark: false)
        let logo = URL(string: "https://app.clomni.ai/v1/images/parity_logo")!
        let size = ClomniTheme.Size.headerLead
        for scale in [1.0, 2, 3] {
            ImageCache.shared.keep(Self.transparent, for: ImageSizing.url(logo, kind: .icon, points: size, scale: scale))
        }
        // The harness draws a disc of this size, or there is nothing to tell apart.
        XCTAssertFalse(Snapshot.isBlank(render(Circle().fill(Color.gray).frame(width: 32, height: 32), size: size,
                                               "control")))

        let bot = ChatAvatarView(avatar: ChatAvatar(url: logo, initial: "E", isBot: true), size: size, theme: theme)
        XCTAssertTrue(Snapshot.isBlank(render(bot, size: size, "bot-logo")), "the bot's logo, nothing under it")
        let row = AvatarView(url: logo, initial: "E", size: size, theme: theme)
        XCTAssertTrue(Snapshot.isBlank(render(row, size: size, "row-logo")), "a row's avatar, nothing under it")

        // Until a picture is there, or when it cannot come, the initial on its disc, as before.
        let missing = URL(string: "https://app.clomni.ai/v1/images/parity_missing")!
        let waiting = ChatAvatarView(avatar: ChatAvatar(url: missing, initial: "E", isBot: true), size: size, theme: theme)
            .environment(\.clomniLoadsRemoteImages, false)
        XCTAssertFalse(Snapshot.isBlank(render(waiting, size: size, "bot-waiting")), "the brand's disc while there is no logo")
        let person = AvatarView(url: missing, initial: "L", size: size, theme: theme)
            .environment(\.clomniLoadsRemoteImages, false)
        XCTAssertFalse(Snapshot.isBlank(render(person, size: size, "person-waiting")), "the grey disc while there is no picture")
    }
}
#endif
