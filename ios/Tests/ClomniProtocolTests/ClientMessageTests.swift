import Foundation
import XCTest
@testable import ClomniProtocol

/// Each client fixture, built the way the UI builds it, must encode to the same JSON.
final class ClientMessageTests: ProtocolTestCase {
    private func assertEncodes(_ message: ClientMessage, as file: String, line: UInt = #line) throws {
        let encoded = try XCTUnwrap(ProtocolJSON.decode(ProtocolJSON.encode(message)), line: line)
        XCTAssertEqual(encoded, try Fixtures.json(file), file, line: line)
    }

    func testText() throws {
        try assertEncodes(ClientMessage(clientId: "6f1c2c8e-1b2a-4c3d-8e9f-0a1b2c3d4e5f",
                                        content: .text("Gedişim bitmədi, pul çıxılmağa davam edir")),
                          as: "45-client-text.json")
    }

    func testButtonReplies() throws {
        let level1 = try Fixtures.message("09-apar-level1-A.json")
        let button = try XCTUnwrap(level1.content.quickReplies?.buttons.first)
        try assertEncodes(ClientMessage(clientId: "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d",
                                        content: .buttonReply(replyTo: level1.id, buttonId: button.id,
                                                              payload: button.payload)),
                          as: "46-client-button-reply.json")
        try assertEncodes(ClientMessage(clientId: "1f2e3d4c-5b6a-4978-8a6b-5c4d3e2f1a0b", content: .back(replyTo: "msg_f10")),
                          as: "47-client-back.json")
        try assertEncodes(ClientMessage(clientId: "5e6f7081-92a3-4b4c-8d5e-6f708192a3b4",
                                        content: .buttonReply(replyTo: "msg_f12", buttonId: "o_no", payload: "end")),
                          as: "51-client-button-end.json")
    }

    func testFormSubmit() throws {
        try assertEncodes(ClientMessage(clientId: "2a3b4c5d-6e7f-4801-9a2b-3c4d5e6f7a8b",
                                        content: .formSubmit(replyTo: "msg_f19", formId: "frm_contact", values: [
                                            "name": "Aysel Məmmədova", "phone": "+994501234567", "email": "",
                                        ])),
                          as: "48-client-form-submit.json")
    }

    func testAttachment() throws {
        try assertEncodes(ClientMessage(clientId: "3c2b1a09-8f7e-4d6c-9b5a-4f3e2d1c0b9a",
                                        content: .attachment(uploadId: "upl_77ab", caption: "Velosiped Nizami küçəsindədir")),
                          as: "49-client-attachment.json")
    }

    func testRating() throws {
        try assertEncodes(ClientMessage(clientId: "6f708192-a3b4-4c5d-9e6f-708192a3b4c5",
                                        content: .ratingSubmit(replyTo: "msg_f28", score: 5, comment: "Tez cavab verdiniz")),
                          as: "52-client-rating.json")
    }

    func testMissingOptionalsGoOutAsNull() throws {
        let attachment = ClientMessage(clientId: "c1", content: .attachment(uploadId: "upl_1", caption: nil))
        XCTAssertEqual(String(decoding: ProtocolJSON.encode(attachment), as: UTF8.self),
                       #"{"client_id":"c1","content":{"caption":null,"upload_id":"upl_1"},"type":"attachment"}"#)
        let rating = ClientMessage(clientId: "c2", content: .ratingSubmit(replyTo: "msg_1", score: 4, comment: nil))
        XCTAssertEqual(String(decoding: ProtocolJSON.encode(rating), as: UTF8.self),
                       #"{"client_id":"c2","content":{"comment":null,"reply_to":"msg_1","score":4},"type":"rating_submit"}"#)
        XCTAssertEqual(ProtocolJSON.parseClientMessage(ProtocolJSON.encode(rating)), rating)
    }

    func testNewClientIdIsALowercaseUUIDv4() throws {
        let first = ClientMessage(content: .text("a"))
        let second = ClientMessage(content: .text("a"))
        XCTAssertNotEqual(first.clientId, second.clientId)
        XCTAssertNotNil(UUID(uuidString: first.clientId))
        XCTAssertEqual(first.clientId, first.clientId.lowercased())
        XCTAssertEqual(Array(first.clientId)[14], "4", "version nibble")
        XCTAssertEqual(first.type, "text")
    }

    func testReadingBackRejectsWhatItCannotSend() {
        XCTAssertNil(ProtocolJSON.parseClientMessage(Data(#"{"client_id":"c","type":"sticker","content":{}}"#.utf8)))
        XCTAssertNil(ProtocolJSON.parseClientMessage(Data(#"{"type":"text","content":{"text":"a"}}"#.utf8)))
        XCTAssertNil(ProtocolJSON.parseClientMessage(Data(#"{"client_id":"c","type":"rating_submit","content":{"reply_to":"m","score":4.5}}"#.utf8)))
        XCTAssertNil(ProtocolJSON.parseClientMessage(Data("nope".utf8)))
        XCTAssertTrue(log.contains("client message.type: unknown client message type \"sticker\""), "\(log.lines)")
    }
}
