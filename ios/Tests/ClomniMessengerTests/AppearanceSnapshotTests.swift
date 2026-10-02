// Snapshots need UIKit: they run on the iOS Simulator (CI's xcodebuild test step), as ChatSnapshotTests does.
#if canImport(UIKit) && canImport(SwiftUI)
import Foundation
import SwiftUI
import UIKit
import XCTest
import ClomniProtocol
import ClomniPresentation
@testable import ClomniMessenger

/// What the panel's appearance settings look like on Home (APPEARANCE-CONTRACT § 5): header styles, the glow, the
/// cards' order, channels off, the three languages, the logo in dark mode, without "Powered by Clomni". Pictures do
/// not load in tests: their primary_soft placeholders show where they go.
@MainActor
final class AppearanceSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_850_720)

    /// The Apar config (protocol fixture 42) with `changes` merged into its sections (`[:]` empties one).
    private func config(_ changes: [String: JSONValue]) throws -> MessengerConfig {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures/42-config-apar.json")
        guard case .object(var json)? = ProtocolJSON.decode(try Data(contentsOf: url)) else { throw XCTSkip("fixture") }
        for (key, value) in changes {
            // An empty object replaces the section; any other object is merged into it.
            if case .object(let section)? = json[key], case .object(let patch) = value, !patch.isEmpty {
                json[key] = .object(section.merging(patch) { $1 })
            } else {
                json[key] = value
            }
        }
        return try XCTUnwrap(ProtocolJSON.parseConfig(ProtocolJSON.encode(.object(json))))
    }

    private func render(_ name: String, _ config: MessengerConfig, language: String = "az", dark: Bool = false,
                        user: String? = "Aysel Məmmədova") throws {
        var snapshot = MessengerSnapshot(config: config, conversations: [PreviewData.conversation].compactMap { $0 },
                                         userName: user)
        snapshot.configLoad = .loaded
        snapshot.conversationsLoad = .loaded
        let screen = HomePresenter(strings: ClomniStrings(language: language, overrides: config.strings),
                                   timeZone: TimeZone(identifier: "UTC")!, now: now).home(snapshot)
        let view = HomeView(screen: screen, theme: ClomniTheme.make(brand: config.brand, dark: dark),
                            actions: MessengerActions())
            .environment(\.clomniLoadsRemoteImages, false)
            .environment(\.colorScheme, dark ? .dark : .light)
            .dynamicTypeSize(.large)
        try Snapshot.assert(Snapshot.render(view, width: 390, height: 844, dark: dark), named: "appearance-\(name)")
    }

    func testHeaderStyles() throws {
        try render("gradient", config([:]))
        try render("solid", config(["brand": ["header_style": "solid", "colors": nil]]))
        try render("image", config(["brand": ["header_style": "image",
                                              "header_image_url": "https://app.clomni.ai/v1/images/header"]]))
        // The glow is behind the header: it shows where it spills out under it, around the cards, solid or not.
        try render("glow", config(["brand": ["glow": true]]))
        try render("glow-solid", config(["brand": ["glow": true, "header_style": "solid", "colors": nil]]))
        try render("derived-colours", config(["brand": ["primary_color": "#0A66C2", "colors": nil]]))
    }

    /// DESIGN-PASS: the logo as it is (or the initial in a circle), the greeting's three sizes, the full logo (here
    /// not loaded, so the logo and the name stand in), the larger ✕.
    func testLogoTitleSizeAndWordmark() throws {
        try render("no-logo", config(["brand": ["logo_url": nil]]))
        try render("title-s", config(["home": ["title_size": "s"]]))
        try render("title-l", config(["home": ["title_size": "l"]]))
        try render("title-l-long", config(["home": ["title_size": "l"],
                                           "strings": ["greeting_line2": "Sifarişiniz, gedişiniz və ya ödənişiniz haqqında yazın"]]))
        try render("wordmark-not-loaded", config(["brand": ["logo_style": "wordmark",
                                                            "wordmark_url": "https://app.clomni.ai/v1/images/img_w"]]))
    }

    func testCardsChannelsAndPoweredBy() throws {
        try render("cards-order", config(["home": ["cards": ["channels", "recent", "send"]]]))
        try render("channels-off", config(["home": ["cards": ["send", "recent"]]]))
        try render("no-powered-by", config(["powered_by": false]))
        try render("team-hidden", config(["team": ["show": false]]))
    }

    func testLanguagesAndNames() throws {
        let plain = try config(["strings": .object([:])])
        try render("az", plain)
        try render("en", plain, language: "en")
        try render("ru", plain, language: "ru")
        try render("anonymous", plain, user: nil)
        try render("custom-texts", config(["strings": ["greeting_line1": "Xoş gəldin, {first_name}!",
                                                       "greeting_line2": "Sualınız var?", "send_card_title": "Yazın"]]))
    }

    func testDarkMode() throws {
        try render("dark", config(["brand": ["logo_dark_url": "https://app.clomni.ai/v1/images/apar-logo-dark"]]), dark: true)
        try render("glow-dark", config(["brand": ["glow": true]]), dark: true)
        try render("dark-without-dark-logo", config(["brand": ["logo_dark_url": nil]]), dark: true)
    }
}
#endif
