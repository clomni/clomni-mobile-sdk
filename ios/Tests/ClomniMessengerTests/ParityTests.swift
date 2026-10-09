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

    /// The avatar on white, 10 pt around it, at scale 2; the colour inside its circle, left of the initial.
    private func middle<Avatar: View>(_ avatar: Avatar, size: Double) -> [Int]? {
        let view = avatar
            .padding(10)
            .background(Color.white)
            .environment(\.displayScale, 2)
        let image = Snapshot.render(view, width: CGFloat(size + 20), dark: false)
        return Snapshot.pixel(image, x: Int((10 + size * 0.2) * 2), y: Int((10 + size / 2) * 2))
    }

    /// The panel's logo with transparent parts: the bot's avatar (in the header and next to its messages) and the
    /// "Ən son mesaj" row show it on what is behind it. It showed a grey disc and the initial through it.
    func testALogoWithTransparentPartsShowsNoDiscBehindIt() throws {
        let theme = PreviewData.theme(dark: false)
        let logo = URL(string: "https://app.clomni.ai/v1/images/parity_logo")!
        let size = ClomniTheme.Size.headerLead
        ImageCache.shared.keep(Self.transparent, for: ImageSizing.url(logo, kind: .icon, points: size, scale: 2))
        let white = [255, 255, 255]

        let bot = ChatAvatarView(avatar: ChatAvatar(url: logo, initial: "E", isBot: true), size: size, theme: theme)
        XCTAssertEqual(middle(bot, size: size), white, "the bot's logo, nothing under it")
        let row = AvatarView(url: logo, initial: "E", size: size, theme: theme)
        XCTAssertEqual(middle(row, size: size), white, "a row's avatar, nothing under it")

        // Until a picture is there, or when it cannot come, the initial on its disc, as before.
        let missing = URL(string: "https://app.clomni.ai/v1/images/parity_missing")!
        let waiting = ChatAvatarView(avatar: ChatAvatar(url: missing, initial: "E", isBot: true), size: size, theme: theme)
            .environment(\.clomniLoadsRemoteImages, false)
        XCTAssertNotEqual(middle(waiting, size: size), white, "the brand's disc while there is no logo")
        let person = AvatarView(url: missing, initial: "L", size: size, theme: theme)
            .environment(\.clomniLoadsRemoteImages, false)
        XCTAssertNotEqual(middle(person, size: size), white, "the grey disc while there is no picture")
    }
}
#endif
