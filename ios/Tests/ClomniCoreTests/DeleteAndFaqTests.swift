import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// SDK 1.0.7: the user deletes their own message (DELETE /conversations/{id}/messages/{message_id}); the FAQ is kept
/// like the news.
final class DeleteAndFaqTests: EngineTestCase {
    /// Sent, then deleted: the server's DELETE, and the deleted copy at once, in the same place.
    func testASentMessageIsDeletedForEveryone() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        let pending = try await phone.engine.sendText("Salam", in: id)
        await expect { await phone.pending(id).isEmpty }
        let last = await phone.messages(id).last
        let sent = try XCTUnwrap(last)
        XCTAssertEqual(sent.clientId, pending.id)

        let outcome = await phone.engine.deleteMessage(sent.id, in: id)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(server.requests("DELETE", "/messages/\(sent.id)").count, 1)
        let latest = await phone.messages(id).last
        let after = try XCTUnwrap(latest)
        XCTAssertEqual(after.id, sent.id)
        XCTAssertEqual(after.seq, sent.seq)
        XCTAssertEqual(after.content, .deleted)
        XCTAssertEqual(userMessages(id).first?["type"], "deleted", "on the server too")
    }

    /// 409 conversation_closed: the message stays as it was.
    func testAClosedConversationKeepsTheMessage() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        _ = try await phone.engine.sendText("Salam", in: id)
        await expect { await phone.pending(id).isEmpty }
        let last = await phone.messages(id).last
        let sent = try XCTUnwrap(last)
        server.setStatus("closed", of: id)

        let outcome = await phone.engine.deleteMessage(sent.id, in: id)
        XCTAssertEqual(outcome, .closed)
        let after = await phone.messages(id).last
        XCTAssertEqual(after, sent)
        // Another refusal (no network) is a failure, not a deletion either.
        server.inject(.offline, "DELETE", "/messages/\(sent.id)")
        server.setStatus("open", of: id)
        let offline = await phone.engine.deleteMessage(sent.id, in: id)
        XCTAssertEqual(offline, .failed)
        let still = await phone.messages(id).last
        XCTAssertEqual(still, sent)
    }

    /// Not sent yet (offline): taken off the outbox, and nothing reaches the server.
    func testAMessageStillInTheOutboxIsTakenOff() async throws {
        let frozen = TestTime()
        let phone = await device(time: frozen)
        let (id, _) = try await conversation(on: phone)
        server.inject(.offline, "POST", "/messages")
        let pending = try await phone.engine.sendText("Yazmadım", in: id)
        await expect { self.server.requests("POST", "/messages").count == 1 && frozen.sleeping == 1 }

        let outcome = await phone.engine.deleteMessage(pending.id, in: id)
        XCTAssertEqual(outcome, .deleted)
        let left = await phone.pending(id)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(server.requests.filter { $0.method == "DELETE" }.isEmpty)
        await phone.engine.networkAvailable()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(userMessages(id).isEmpty, "it never went")
    }

    /// Deleted while its POST was out: it reached the server all the same, so it is deleted there as soon as it lands.
    func testAMessageDeletedOnItsWayIsDeletedWhenItLands() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        server.hold("POST", "/messages")
        let pending = try await phone.engine.sendText("Səhv yazdım", in: id)
        await expect { self.server.heldCount == 1 }

        let outcome = await phone.engine.deleteMessage(pending.id, in: id)
        XCTAssertEqual(outcome, .deleted)
        server.release()
        await expect { self.userMessages(id).first?["type"] == "deleted" }
        await expect { await phone.messages(id).last?.content == .deleted }
        let left = await phone.pending(id)
        XCTAssertTrue(left.isEmpty)
    }

    /// The socket's own copy of the user's message arriving before the POST's answer takes it off the outbox too; that
    /// is no deletion, and nothing is deleted on the server.
    func testTheSocketsCopyFirstIsNoDeletion() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        server.hold("POST", "/messages")
        _ = try await phone.engine.sendText("Salam", in: id)
        await expect { self.server.heldCount == 1 }
        let created = try XCTUnwrap(server.storedMessages(id).last)
        server.emit("message.created", created)
        await expect { await phone.pending(id).isEmpty }
        server.release()
        await expect { await phone.messages(id).last?.id == created["id"]?.stringValue }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(server.requests.filter { $0.method == "DELETE" }.isEmpty)
        XCTAssertEqual(userMessages(id).first?["type"], "text")
    }

    func testTheFaqIsKeptWithItsETagAndOpeningIsReported() async throws {
        server.faqBody = try XCTUnwrap(ProtocolJSON.decode(Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("protocol/fixtures/110-faq.json"))))
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let first = await phone.engine.refreshFaq()
        XCTAssertEqual(first.map(\.id), ["faq_12", "faq_9", "faq_15", "faq_16"])
        let again = await phone.engine.refreshFaq()
        XCTAssertEqual(again.count, 4, "304: the kept ones")
        XCTAssertEqual(server.requests("GET", "/faq").last?.headers["If-None-Match"], server.faqETag)

        let relaunched = await device(cache: phone.cache, vault: phone.vault)
        let fromDisk = await relaunched.engine.faq
        XCTAssertEqual(fromDisk.count, 4, "from disk before the server answers")

        await phone.engine.faqOpened("faq_9")
        let event = try XCTUnwrap(server.requests("POST", "/events").last)
        XCTAssertEqual(body(event)?["event"], "faq_opened")
        XCTAssertEqual(body(event)?["data"]?["faq_id"], "faq_9")

        await phone.engine.logout()
        let gone = await phone.engine.faq
        XCTAssertEqual(gone, [], "nothing kept after logout")
    }
}
