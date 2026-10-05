import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// A new conversation is created with its first message, not when the messenger opens: opening and closing must not
/// leave empty conversations in the panel.
final class DraftConversationTests: EngineTestCase {
    func testOpeningAndClosingAsksTheServerNothing() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let before = server.requests.count
        let draft = await phone.engine.draftConversation(openedFrom: "help")
        XCTAssertTrue(ClomniEngine.isDraft(draft))
        // What an open conversation screen does.
        try await phone.engine.refreshConversation(draft)
        try await phone.engine.loadMessages(in: draft)
        _ = try await phone.engine.loadOlder(in: draft)
        await phone.engine.markRead(in: draft)
        await phone.engine.setTyping(true, in: draft)
        await phone.engine.setTyping(false, in: draft)
        XCTAssertEqual(server.requests.count, before, "\(server.requests.dropFirst(before).map(\.url.path))")
        XCTAssertTrue(server.requests("POST", "/conversations").isEmpty)
    }

    /// `conversation.starts_with_flow`: the conversation is created as the draft opens, with the draft's client_id,
    /// and the flow's first message is there before the user writes; their first message does not create another.
    func testAConversationThatStartsWithAFlowIsCreatedWhenItOpens() async throws {
        server.startsWithFlow = true
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        _ = await phone.engine.refreshConfig(language: "az")
        let draft = await phone.engine.draftConversation(openedFrom: "home")
        await expect { await phone.engine.resolved(draft) != draft }
        let id = await phone.engine.resolved(draft)
        let creates = server.requests("POST", "/conversations")
        XCTAssertEqual(creates.count, 1)
        XCTAssertEqual(body(creates.first)?["client_id"]?.stringValue, String(draft.dropFirst(ClomniEngine.draftPrefix.count)))
        XCTAssertEqual(body(creates.first)?["opened_from"]?.stringValue, "home")
        let messages = await phone.messages(id)
        XCTAssertEqual(messages.first?.sender.type, .bot)

        try await phone.engine.sendText("Salam", in: draft)
        await expect { self.userMessages(id).count == 1 }
        XCTAssertEqual(server.requests("POST", "/conversations").count, 1)
    }

    /// A message written while the opening's create is on its way waits for it: one POST /conversations.
    func testAMessageDuringTheFlowsCreateMakesNoSecondConversation() async throws {
        server.startsWithFlow = true
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        _ = await phone.engine.refreshConfig(language: "az")
        let draft = await phone.engine.draftConversation(openedFrom: nil)
        try await phone.engine.sendText("Salam", in: draft)
        await expect { await phone.engine.resolved(draft) != draft }
        let id = await phone.engine.resolved(draft)
        await expect { self.userMessages(id).count == 1 }
        XCTAssertEqual(server.requests("POST", "/conversations").count, 1)
    }

    func testTheFirstMessageCreatesTheConversationOnce() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let created = Created()
        await phone.engine.observe { change in
            if case .conversationCreated(let draft, let id) = change { created.add(draft, id) }
        }
        let draft = await phone.engine.draftConversation(openedFrom: "help")
        try await phone.engine.sendText("Salam", in: draft)
        try await phone.engine.sendText("Gedişim bitmədi", in: draft)
        await expect { await phone.engine.resolved(draft) != draft && created.pairs.count == 1 }
        let id = await phone.engine.resolved(draft)
        await expect { await phone.pending(id).isEmpty && self.userMessages(id).count == 2 }
        let pendingOnDraft = await phone.pending(draft)
        XCTAssertTrue(pendingOnDraft.isEmpty)

        XCTAssertEqual(created.pairs.map(\.0), [draft])
        XCTAssertEqual(created.pairs.map(\.1), [id])
        let creates = server.requests("POST", "/conversations")
        XCTAssertEqual(creates.count, 1)
        XCTAssertEqual(body(creates.first)?["opened_from"]?.stringValue, "help")
        XCTAssertEqual(server.requests("POST", "/messages").count, 2)
        XCTAssertEqual(userMessages(id).compactMap { $0["content"]?["text"]?.stringValue }, ["Salam", "Gedişim bitmədi"])
        // The flow's first message came with the conversation.
        let messages = await phone.messages(id)
        XCTAssertEqual(messages.first?.sender.type, .bot)

        // A screen still holding the draft's id sends into the conversation.
        try await phone.engine.sendText("Üçüncü", in: draft)
        await expect { self.userMessages(id).count == 3 }
        XCTAssertEqual(server.requests("POST", "/conversations").count, 1)
    }

    /// Offline, the outbox keeps the order: the conversation is created first (once), then the message goes.
    func testOfflineTheConversationIsCreatedThenTheMessageSent() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        server.inject(.offline, "POST", "/conversations")
        server.inject(.offline, "POST", "/conversations")
        let draft = await phone.engine.draftConversation(openedFrom: nil)
        let pending = try await phone.engine.sendText("Salam", in: draft)
        let sent = await drive(time) {
            let id = await phone.engine.resolved(draft)
            return id != draft && self.userMessages(id).count == 1
        }
        XCTAssertTrue(sent)
        let id = await phone.engine.resolved(draft)
        XCTAssertEqual(server.requests("POST", "/conversations").count, 3, "two lost to the network, one created")
        XCTAssertEqual(server.requests("POST", "/messages").count, 1, "only after the conversation exists")
        XCTAssertEqual(userMessages(id).first?["client_id"]?.stringValue, pending.id)
    }

    /// The server started the conversation but its answer was lost: the retry carries the same client_id (the
    /// draft's UUID), the server answers 200 with that conversation, and there is one conversation, not two.
    func testALostAnswerStartsOneConversation() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        server.inject(.lostResponse, "POST", "/conversations")
        let draft = await phone.engine.draftConversation(openedFrom: "help")
        try await phone.engine.sendText("Salam", in: draft)
        let sent = await drive(time) {
            let id = await phone.engine.resolved(draft)
            return id != draft && self.userMessages(id).count == 1
        }
        XCTAssertTrue(sent)
        let creates = server.requests("POST", "/conversations")
        XCTAssertEqual(creates.count, 2)
        let clientIds = creates.map { self.body($0)?["client_id"]?.stringValue }
        XCTAssertEqual(clientIds, Array(repeating: String(draft.dropFirst(ClomniEngine.draftPrefix.count)), count: 2))
        try await phone.engine.refreshConversations()
        let conversations = await phone.engine.conversations()
        let id = await phone.engine.resolved(draft)
        XCTAssertEqual(conversations.map(\.id), [id], "one conversation")
    }

    /// The draft's message is on disk: the next launch creates the conversation with its `opened_from`, then sends.
    func testADraftsMessageSurvivesARestart() async throws {
        let frozen = TestTime()
        let before = await device(time: frozen)
        try await before.engine.loginUnidentifiedUser()
        server.inject(.offline, "POST", "/conversations")
        let draft = await before.engine.draftConversation(openedFrom: "ride_screen")
        let pending = try await before.engine.sendText("Yazdım və çıxdım", in: draft)
        await expect { await before.pending(draft).first?.attempts == 1 }

        let after = await device(cache: before.cache, vault: before.vault)
        let fromDisk = await after.pending(draft).map(\.id)
        XCTAssertEqual(fromDisk, [pending.id], "shown at once, from disk")
        await after.engine.connect()
        await expect { await after.engine.resolved(draft) != draft }
        let id = await after.engine.resolved(draft)
        await expect { self.userMessages(id).count == 1 }
        XCTAssertEqual(body(server.requests("POST", "/conversations").last)?["opened_from"]?.stringValue, "ride_screen")
        XCTAssertEqual(server.requests("POST", "/conversations").count, 2)
    }
}

private final class Created: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [(String, String)] = []

    func add(_ draft: String, _ id: String) {
        lock.lock()
        defer { lock.unlock() }
        list.append((draft, id))
    }

    var pairs: [(String, String)] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }
}
