import Foundation
import XCTest
import ClomniProtocol
import ClomniCore
@testable import ClomniPresentation

/// CM-346 § 5.4: with `config.conversation.single` (the inbox's lock_to_single_conversation), "Bizə mesaj göndərin"
/// and every other way to a new conversation open the conversation the server would resume (`resume_conversation_id`
/// of GET /conversations), with its history, and not an empty new one that jumps to the old one at the first message
/// (TestFlight #21, 17:18). Without the setting, or when the server names none, a new one as before.
@MainActor
final class SingleConversationTests: XCTestCase {
    private func config(single: Bool?) -> MessengerConfig {
        let conversation = single.map { #","conversation":{"single":\#($0)}"# } ?? ""
        return ProtocolJSON.parseConfig(Data(#"{"brand":{"name":"Example"}\#(conversation)}"#.utf8))!
    }

    func testTheSetting() {
        XCTAssertTrue(config(single: true).singleConversation)
        XCTAssertFalse(config(single: false).singleConversation)
        XCTAssertFalse(config(single: nil).singleConversation, "absent: off")
    }

    func testWhichConversationOpens() {
        XCTAssertEqual(SingleConversation.existing(resume: "conv_open", config: config(single: true)), "conv_open",
                       "single, and one the server resumes: that one")
        XCTAssertNil(SingleConversation.existing(resume: nil, config: config(single: true)),
                     "single, the server resumes none (only closed ones, an idle bot's, a finished flow's): a new one")
        XCTAssertNil(SingleConversation.existing(resume: "conv_open", config: config(single: false)), "single off: a new one")
        XCTAssertNil(SingleConversation.existing(resume: "conv_open", config: nil))
    }

    /// Home's "Bizə mesaj göndərin" (and the list's): the conversation the server resumes; no draft is made.
    func testHomeOpensTheResumedConversation() async {
        let source = FakeSource()
        let single = config(single: true)
        await source.set(cached: single)
        await source.set(resume: "conv_open")
        let controller = HomeController(source: source, language: "az", userName: nil, config: single)
        let opened = await controller.startConversation(openedFrom: nil)
        XCTAssertEqual(opened, "conv_open")
        let drafts = await source.starts
        XCTAssertEqual(drafts, 0, "no new conversation")

        await source.set(resume: nil)
        let none = await controller.startConversation(openedFrom: nil)
        XCTAssertTrue(none.hasPrefix("draft_"), "none to resume: a new one, \(none)")

        await source.set(resume: "conv_open")
        let plain = HomeController(source: source, language: "az", userName: nil, config: config(single: false))
        let asks = await source.resumeAsks
        let new = await plain.startConversation(openedFrom: nil)
        XCTAssertTrue(new.hasPrefix("draft_"), "single off: a new one, \(new)")
        let after = await source.resumeAsks
        XCTAssertEqual(after, asks, "and the server is not asked")
    }

    /// `Clomni.presentNewConversation`: the same rule.
    func testPresentNewConversationOpensTheResumedConversation() async {
        let session = FakeSession()
        let single = config(single: true)
        await session.set(loggedIn: true, cached: single, fresh: single)
        await session.set(resume: "conv_open")
        let coordinator = MessengerCoordinator(session: session)
        await coordinator.start()
        let id = await coordinator.presentNewConversation(source: "ride")
        XCTAssertEqual(id, "conv_open")
        XCTAssertEqual(coordinator.route, .conversation("conv_open"))
        let calls = await session.calls
        XCTAssertFalse(calls.contains { $0.hasPrefix("draft") }, "\(calls)")

        await session.set(resume: nil)
        coordinator.dismiss()
        let new = await coordinator.presentNewConversation()
        XCTAssertEqual(new?.hasPrefix("draft_"), true, "none to resume: a new one")
    }
}
