import Foundation
import XCTest
@testable import ClomniProtocol

/// Fixtures 66–74 (DESIGN-PASS-3 F1): a message's `reply_to`, the client's, and `conversation.flow`.
final class ReplyAndFlowTests: ProtocolTestCase {
    func testAMessageCarriesItsQuote() throws {
        let leyla = Sender(type: .operator, name: "Leyla")
        XCTAssertEqual(try Fixtures.message("66-reply-user-to-operator.json").replyTo, ReplyRef(
            id: "msg_f65", sender: leyla,
            excerpt: "Ödənişi kartla etmisiniz, yoxsa balansdan? Qəbzin şəklini də göndərə bilərsiniz, yoxlayaq.",
            kind: "text"))
        let user = Sender(type: .user, name: "Aysel Məmmədova")
        XCTAssertEqual(try Fixtures.message("67-reply-operator-to-image.json").replyTo,
                       ReplyRef(id: "msg_f62", sender: user, excerpt: "qebz.jpg", kind: "image"))
        let deleted = try Fixtures.message("68-reply-to-deleted.json")
        XCTAssertEqual(deleted.replyTo, ReplyRef(id: "msg_f60", sender: user, excerpt: nil, kind: "text"))
        XCTAssertEqual(try JSONDecoder().decode(Message.self, from: try JSONEncoder().encode(deleted)), deleted,
                       "kept on disk with its quote")
        XCTAssertNil(try Fixtures.message("01-text-bot.json").replyTo)
    }

    func testABrokenQuoteLeavesTheMessage() throws {
        let message = try Fixtures.message("70-invalid-reply-to-without-kind.json")
        XCTAssertEqual(message.content, .text("Bəli"))
        XCTAssertNil(message.replyTo)
        XCTAssertTrue(log.contains("msg_f70:"), "\(log.lines)")
    }

    func testTheClientsReply() throws {
        let message = ClientMessage(clientId: "0b7d4f2e-9a61-4c8b-b3f0-5e2d1a7c6b94", content: .text("Bəli, kartla ödəmişdim"),
                                    replyTo: "msg_f65")
        XCTAssertEqual(ProtocolJSON.decode(ProtocolJSON.encode(message)), try Fixtures.json("69-client-text-reply.json"))
        let file = ClientMessage(content: .attachment(uploadId: "upl_1", caption: nil), replyTo: "msg_f65")
        XCTAssertEqual(ProtocolJSON.parseClientMessage(ProtocolJSON.encode(file)), file)
        XCTAssertNil(ProtocolJSON.decode(ProtocolJSON.encode(ClientMessage(content: .text("a"))))?["content"]?["reply_to"])
    }

    func testTheConversationsFlow() throws {
        let flows = try ["71-event-flow-menu.json", "72-event-flow-text.json", "73-event-flow-ended.json",
                         "74-invalid-flow-awaiting-unknown.json"].map { file -> Conversation.FlowState? in
            guard case .conversationUpdated(let update) = try Fixtures.event(file).data else { return nil }
            return update.flow
        }
        XCTAssertEqual(flows, [.init(active: true, awaiting: "menu", flowId: "flw_example_az", nodeId: "S"),
                               .init(active: true, awaiting: "text", flowId: "flw_example_az", nodeId: "U"),
                               .init(active: false), .init(active: true, awaiting: "buttons", flowId: "flw_example_az", nodeId: "S")])
        XCTAssertEqual(flows.map { $0?.holdsTheComposer }, [true, false, false, true],
                       "a menu holds the composer, text and an ended flow do not; an unknown value is not text")
    }
}
