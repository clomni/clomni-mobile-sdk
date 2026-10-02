import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// Brief 8 · 5.5, case by case, against the fake server.
class EngineTestCase: XCTestCase {
    var time = TestTime()
    var server = FakeServer(time: TestTime())
    let hub = SocketHub()
    private var devices: [Device] = []

    override func setUp() async throws {
        time = TestTime()
        server = FakeServer(time: time)
        let hub = hub
        server.onFrame { hub.push($0) }
    }

    override func tearDown() async throws {
        for device in devices {
            await device.engine.disconnect()
            device.cache.clear()
        }
        devices = []
    }

    func device(cache: DiskCache? = nil, vault: MemorySecureStore? = nil, time: TestTime? = nil) async -> Device {
        let device = await Device(server, time: time ?? self.time, cache: cache, vault: vault)
        hub.add(device.socket)
        devices.append(device)
        return device
    }

    /// A logged-in device with a new conversation; returns the conversation and its first (button) message.
    func conversation(on device: Device, user: String? = nil) async throws -> (id: String, question: Message) {
        if let user {
            try await device.engine.loginUser(UserIdentity(userId: user), userHash: "hash_\(user)")
        } else {
            try await device.engine.loginUnidentifiedUser()
        }
        let conversation = try await device.engine.startConversation(openedFrom: "test")
        let first = await device.messages(conversation.id).first
        let question = try XCTUnwrap(first)
        return (conversation.id, question)
    }

    func buttons(_ message: Message) throws -> [MessageContent.Button] {
        guard case .quickReplies(let replies) = message.content else { throw ClomniError.rejected("not quick replies") }
        return replies.buttons
    }

    func userMessages(_ conversationId: String) -> [JSONValue] {
        server.storedMessages(conversationId).filter { $0["sender"]?["type"] == "user" }
    }

    func body(_ request: HTTPRequest?) -> JSONValue? {
        request?.body.flatMap { ProtocolJSON.decode($0) }
    }
}

final class EdgeCaseTests: EngineTestCase {
    /// "Düyməyə iki dəfə tez basılır": the client disables the buttons, so one reply goes out.
    func testTwoQuickTapsSendOneReply() async throws {
        let phone = await device()
        let (id, question) = try await conversation(on: phone)
        let choices = try buttons(question)
        let pending = try await phone.engine.reply(to: question, with: choices[0])
        XCTAssertEqual(pending.preview, "Gediş problemi")
        do {
            try await phone.engine.reply(to: question, with: choices[1])
            XCTFail("the second tap must not send")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("already answered"))
        }
        await expect { await phone.pending(id).isEmpty }
        XCTAssertEqual(server.requests("POST", "/messages").count, 1)
        let last = await phone.messages(id).last
        let reply = try XCTUnwrap(last)
        XCTAssertEqual(reply.clientId, pending.id, "the server's copy replaced the optimistic bubble")
        XCTAssertEqual(reply.content, .text("Gediş problemi"))
    }

    /// The same, when the second answer comes from a device that had not heard of the first: 409 already_answered.
    func testAnAnswerAlreadyGivenIs409AndDisablesTheButtons() async throws {
        let phone = await device()
        let tablet = await device()
        let (id, question) = try await conversation(on: phone, user: "7")
        try await tablet.engine.loginUser(UserIdentity(userId: "7"), userHash: "hash_7")
        try await tablet.engine.loadMessages(in: id)
        try await phone.engine.reply(to: question, with: try buttons(question)[0])
        await expect { await phone.pending(id).isEmpty }

        let tabletCopy = await tablet.messages(id).first
        let stale = try XCTUnwrap(tabletCopy)
        let canAnswerBefore = await tablet.engine.canAnswer(stale)
        XCTAssertTrue(canAnswerBefore, "the tablet has no socket, so it has not heard")
        try await tablet.engine.reply(to: stale, with: try buttons(stale)[1])
        await expect { await tablet.pending(id).isEmpty }
        await expect("the tablet reloads the message") { await tablet.messages(id).first?.flow?.interactive == false }
        let reloaded = await tablet.messages(id).first
        let canAnswerAfter = await tablet.engine.canAnswer(try XCTUnwrap(reloaded))
        XCTAssertFalse(canAnswerAfter)
        XCTAssertEqual(userMessages(id).count, 1, "the server kept the first answer only")
        XCTAssertEqual(server.requests("POST", "/messages").count, 2)
    }

    /// "Köhnə mesajın düyməsi": an answer to a step the flow has left is 409 stale_interaction.
    func testAnOldButtonIs409StaleInteraction() async throws {
        let phone = await device()
        let (id, question) = try await conversation(on: phone)
        let next = server.botAsks("Növbəti addım", buttons: ["A", "B"], in: id, silently: true)
        try await phone.engine.reply(to: question, with: try buttons(question)[0])
        await expect { await phone.messages(id).count == 2 }
        let nothingPending = await phone.pending(id).isEmpty
        XCTAssertTrue(nothingPending)
        let newest = await phone.messages(id).last
        let latest = try XCTUnwrap(newest)
        XCTAssertEqual(latest.id, next["id"]?.stringValue)
        let canAnswerOld = await phone.engine.canAnswer(question)
        let canAnswerNew = await phone.engine.canAnswer(latest)
        XCTAssertFalse(canAnswerOld)
        XCTAssertTrue(canAnswerNew)
        XCTAssertTrue(userMessages(id).isEmpty)
    }

    /// "Göndərərkən internet kəsildi": the outbox repeats the message with its client id; after three failures it
    /// is marked failed, and a retry sends it.
    func testOfflineMessageIsRetriedThenFailedThenRetriedByHand() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        for _ in 0..<3 { server.inject(.offline, "POST", "/messages") }
        let pending = try await phone.engine.sendText("Salam", in: id)
        let failed = await drive(time) { await phone.pending(id).first?.state == .failed }
        XCTAssertTrue(failed)
        let posts = server.requests("POST", "/messages")
        XCTAssertEqual(posts.count, 3)
        XCTAssertEqual(Set(posts.compactMap { self.body($0)?["client_id"]?.stringValue }), [pending.id])
        let attempts = await phone.pending(id).first?.attempts
        XCTAssertEqual(attempts, 3)
        XCTAssertTrue(time.waits.contains(1) && time.waits.contains(2), "\(time.waits)")

        try await phone.engine.retry(pending.id)
        await expect { await phone.pending(id).isEmpty }
        XCTAssertEqual(userMessages(id).count, 1)
        let delivered = await phone.messages(id).last?.clientId
        XCTAssertEqual(delivered, pending.id)
        do {
            try await phone.engine.retry(pending.id)
            XCTFail("nothing left to retry")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("nothing to retry"))
        }
    }

    /// Acceptance: "Oflayn yazılan mesaj bir dəfə çatdırılır". The server took the message but its answer was lost;
    /// the repeat carries the same client id, and both the server and the store end up with one message.
    func testAMessageWhoseAnswerWasLostArrivesOnce() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        server.inject(.lostResponse, "POST", "/messages")
        let pending = try await phone.engine.sendText("Gedişim bitmədi", in: id)
        let delivered = await drive(time) { await phone.pending(id).isEmpty }
        XCTAssertTrue(delivered)
        XCTAssertEqual(server.requests("POST", "/messages").count, 2)
        XCTAssertEqual(userMessages(id).count, 1)
        // The socket brings the same message later still.
        await phone.online()
        server.emit("message.created", try XCTUnwrap(userMessages(id).first))
        try await Task.sleep(nanoseconds: 50_000_000)
        let mine = await phone.messages(id).filter { $0.clientId == pending.id }
        XCTAssertEqual(mine.count, 1)
    }

    /// "…tətbiq bağlansa": the outbox is on disk, and the next launch sends what is in it.
    func testTheOutboxSurvivesARestart() async throws {
        let frozen = TestTime()
        let before = await device(time: frozen)
        let (id, _) = try await conversation(on: before)
        server.inject(.offline, "POST", "/messages")
        let pending = try await before.engine.sendText("Yazdım və çıxdım", in: id)
        await expect { await before.pending(id).first?.attempts == 1 }

        let after = await device(cache: before.cache, vault: before.vault)
        let fromDisk = await after.pending(id).map(\.id)
        XCTAssertEqual(fromDisk, [pending.id], "shown at once, from disk")
        await after.engine.connect()
        await expect { await after.pending(id).isEmpty }
        let delivered = await after.messages(id).last?.clientId
        XCTAssertEqual(delivered, pending.id)
        XCTAssertEqual(userMessages(id).count, 1)
    }

    /// "WS kəsildi": reconnect after 1 s, then fetch what was missed with after_seq.
    func testADroppedSocketReconnectsAndCatchesUp() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        await expect { self.server.requests("GET", "/conversations").count == 1 }
        try XCTUnwrap(phone.socket.live).close()
        server.botSays("Siz yox ikən yazdıq", in: id)
        let reconnected = await drive(time) { phone.socket.connections.count == 2 }
        XCTAssertTrue(reconnected)
        phone.socket.ready()
        await expect { await phone.messages(id).count == 2 }
        XCTAssertEqual(server.requests("GET", "/messages").last?.url.query, "after_seq=1&limit=100")
        let caughtUp = await phone.messages(id).last?.content
        XCTAssertEqual(caughtUp, .text("Siz yox ikən yazdıq"))
    }

    /// "Eyni mesaj REST və WS ilə": one message.
    func testTheSameMessageOverRestAndSocketIsKeptOnce() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        let pending = try await phone.engine.sendText("Salam", in: id)
        await expect { await phone.pending(id).isEmpty }
        try await Task.sleep(nanoseconds: 20_000_000)
        let copies = await phone.messages(id).filter { $0.clientId == pending.id }.count
        XCTAssertEqual(copies, 1)
        let count = await phone.messages(id).count
        XCTAssertEqual(count, 2)
    }

    /// "seq boşluğu (40 → 42)": 41 is fetched over REST.
    func testASeqGapIsFetched() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        server.botSays("itən", in: id, silently: true)
        server.botSays("gələn", in: id)
        await expect { await phone.messages(id).map(\.seq) == [1, 2, 3] }
        XCTAssertEqual(server.requests("GET", "/messages").last?.url.query, "after_seq=1&limit=100")
    }

    /// "İki cihaz": a button pressed on one phone is disabled on the other through message.updated.
    func testAButtonPressedOnOneDeviceIsDisabledOnTheOther() async throws {
        let phone = await device()
        let tablet = await device()
        let (id, question) = try await conversation(on: phone, user: "9")
        try await tablet.engine.loginUser(UserIdentity(userId: "9"), userHash: "hash_9")
        try await tablet.engine.loadMessages(in: id)
        await tablet.online()
        let canAnswerBefore = await tablet.engine.canAnswer(question)
        XCTAssertTrue(canAnswerBefore)
        try await phone.engine.reply(to: question, with: try buttons(question)[1])
        await expect { await tablet.messages(id).count == 2 }
        let tabletCopy = await tablet.messages(id).first
        let updated = try XCTUnwrap(tabletCopy)
        let canAnswerAfter = await tablet.engine.canAnswer(updated)
        XCTAssertFalse(canAnswerAfter)
        let reply = await tablet.messages(id).last?.content
        XCTAssertEqual(reply, .text("Məlumat"))
    }

    /// "Anonim → login": the anonymous conversations stay; logout deletes everything local.
    func testAnonymousThenLoginKeepsTheConversationAndLogoutClearsAll() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        try await phone.engine.loginUser(UserIdentity(userId: "42", email: "aysel@example.com"), userHash: "hash_42")
        let kept = await phone.engine.conversations().map(\.id)
        XCTAssertEqual(kept, [id])
        try await phone.engine.refreshConversations()
        let merged = await phone.engine.conversations().map(\.id)
        XCTAssertEqual(merged, [id], "merged on the server")
        XCTAssertEqual(server.conversation(id)?.user, "usr_42")

        await phone.engine.logout()
        let noConversations = await phone.engine.conversations().isEmpty
        XCTAssertTrue(noConversations)
        let noMessages = await phone.messages(id).isEmpty
        XCTAssertTrue(noMessages)
        let loggedIn = await phone.engine.isLoggedIn
        XCTAssertFalse(loggedIn)
        XCTAssertFalse(FileManager.default.fileExists(atPath: phone.cache.directory.path))
        XCTAssertNil(phone.vault.read("session"))
        XCTAssertEqual(server.requests.last?.method, "DELETE")
    }

    /// Another identified user on the same phone does not see the first one's conversations.
    func testAnotherUserStartsClean() async throws {
        let phone = await device()
        _ = try await conversation(on: phone, user: "1")
        try await phone.engine.loginUser(UserIdentity(userId: "2"), userHash: "hash_2")
        let noConversations = await phone.engine.conversations().isEmpty
        XCTAssertTrue(noConversations)
    }

    /// "Boş mətn": nothing is sent.
    func testEmptyAndOverlongTextsAreNotSent() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        for text in ["", "  \n "] {
            do {
                try await phone.engine.sendText(text, in: id)
                XCTFail("empty text sent")
            } catch {
                XCTAssertEqual(error as? ClomniError, .rejected("empty text"))
            }
        }
        await phone.engine.refreshConfig()
        do {
            try await phone.engine.sendText(String(repeating: "a", count: 51), in: id)
            XCTFail("over the config's text_chars")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("text over the limit"))
        }
        let sent = try await phone.engine.sendText("  Salam  ", in: id)
        XCTAssertEqual(sent.message.content, .text("Salam"))
        await expect { await phone.pending(id).isEmpty }
        XCTAssertEqual(server.requests("POST", "/messages").count, 1)
    }
}
