import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

/// CM-346: the conversations' unread count on their tab: nothing at 0, the number up to 99, then "99+"; VoiceOver
/// reads the tab with the count, "Söhbətlər, 7 oxunmamış".
final class TabBadgeTests: XCTestCase {
    private var tabbed: MessengerConfig { ProtocolJSON.parseConfig(Fixture.data("109-config-tab-bar-faq.json"))! }

    private func messagesTab(unread: Int, language: String = "az") -> TabBar.Item? {
        var snapshot = MessengerSnapshot(config: tabbed)
        snapshot.unreadTotal = unread
        let strings = ClomniStrings(language: language, overrides: language == "az" ? tabbed.strings : [:])
        return HomePresenter(strings: strings, now: Date()).tabBar(snapshot)?.items.first { $0.tab == .messages }
    }

    func testTheBadgesText() {
        XCTAssertNil(TabBar.badge(0), "nothing unread: no badge")
        XCTAssertNil(TabBar.badge(-1))
        XCTAssertEqual(TabBar.badge(7), "7")
        XCTAssertEqual(TabBar.badge(99), "99")
        XCTAssertEqual(TabBar.badge(100), "99+")
        XCTAssertEqual(messagesTab(unread: 100)?.badge, "99+")
        XCTAssertNil(messagesTab(unread: 0)?.badge)
    }

    func testVoiceOverReadsTheCount() {
        XCTAssertEqual(messagesTab(unread: 7)?.accessibilityLabel, "Söhbətlər, 7 oxunmamış")
        XCTAssertEqual(messagesTab(unread: 120)?.accessibilityLabel, "Söhbətlər, 120 oxunmamış", "the count, not 99+")
        XCTAssertEqual(messagesTab(unread: 0)?.accessibilityLabel, "Söhbətlər")
        XCTAssertEqual(messagesTab(unread: 7, language: "en")?.accessibilityLabel, "Chats, 7 unread")
    }
}
