import Foundation
import XCTest
@testable import ClomniProtocol

/// SDK 1.0.7's protocol: deleted messages, the tab bar, news on Home and the FAQ (fixtures 107–115).
final class Release107Tests: ProtocolTestCase {
    func testTheUsersDeletedMessageKeepsWhoAndWhenOnly() throws {
        let message = try Fixtures.message("107-deleted-user-message.json")
        XCTAssertEqual(message.type, "deleted")
        XCTAssertEqual(message.content, .deleted)
        XCTAssertTrue(message.isDeleted)
        XCTAssertEqual(message.sender.type, .user)
        XCTAssertEqual(message.seq, 21)
        XCTAssertNil(message.replyTo)
        // Kept on disk and read back the same.
        let stored = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(Message.self, from: stored), message)
    }

    func testAnOperatorsMessageDeletedInThePanelComesAsAnUpdate() throws {
        let event = try Fixtures.event("108-event-message-deleted-by-operator.json")
        guard case .messageUpdated(let message) = event.data else { return XCTFail("\(event.data)") }
        XCTAssertEqual(message.id, "msg_f108")
        XCTAssertEqual(message.content, .deleted)
        XCTAssertEqual(message.sender.type, .operator)
        XCTAssertEqual(message.fallbackText, "This message was deleted")
    }

    func testDeletedCopyDropsTheContentAndTheQuote() throws {
        let original = try Fixtures.message("66-reply-user-to-operator.json")
        XCTAssertNotNil(original.replyTo)
        let deleted = original.deleted()
        XCTAssertEqual(deleted.type, "deleted")
        XCTAssertEqual(deleted.content, .deleted)
        XCTAssertNil(deleted.replyTo)
        XCTAssertNil(deleted.flow)
        XCTAssertEqual([deleted.id, deleted.clientId, deleted.conversationId], [original.id, original.clientId, original.conversationId])
        XCTAssertEqual(deleted.seq, original.seq)
        XCTAssertEqual(deleted.createdAt, original.createdAt)
        XCTAssertEqual(deleted.sender, original.sender)
        XCTAssertFalse(deleted.fallbackText.contains(original.fallbackText), "nothing of the text is kept")
    }

    func testTheConfigsTabBarNewsOnHomeAndFaq() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("109-config-tab-bar-faq.json")))
        XCTAssertTrue(config.home.tabBar)
        XCTAssertEqual(config.home.newsOnHome, 1)
        XCTAssertTrue(config.faqEnabled)
        XCTAssertTrue(config.home.cards.contains(.faq))
        XCTAssertEqual(config.strings["tab_faq"], "Suallar")
    }

    func testAnOlderConfigHasNoTabBarTwoNewsAndNoFaq() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"home": {"cards": ["send", "news"]}}"#.utf8)))
        XCTAssertFalse(config.home.tabBar)
        XCTAssertEqual(config.home.newsOnHome, 2)
        XCTAssertFalse(config.faqEnabled)
        XCTAssertFalse(config.home.cards.contains(.faq))
        for value in [0, 4, -1] {
            let json = #"{"home": {"news_on_home": \#(value)}, "faq": {"enabled": "yes"}}"#
            let odd = try XCTUnwrap(ProtocolJSON.parseConfig(Data(json.utf8)))
            XCTAssertEqual(odd.home.newsOnHome, 2, "\(value)")
            XCTAssertFalse(odd.faqEnabled)
        }
    }

    func testTheFaqInThePanelsOrder() throws {
        let faq = try XCTUnwrap(ProtocolJSON.parseFaq(try Fixtures.data("110-faq.json")))
        XCTAssertEqual(faq.map(\.id), ["faq_12", "faq_9", "faq_15", "faq_16"])
        XCTAssertEqual(faq[0].question, "Gedişin pulunu necə qaytara bilərəm?")
        XCTAssertTrue(faq[0].answer.hasPrefix("Gediş bitəndən sonra **24 saat**"))
        XCTAssertNotNil(faq[0].updatedAt)
        XCTAssertEqual(ProtocolJSON.parseFaq(try Fixtures.data("111-faq-empty.json")), [])
        XCTAssertNil(ProtocolJSON.parseFaq(Data("[]".utf8)), "not an object")
    }
}
