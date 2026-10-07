import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

final class EngineTests: EngineTestCase {
    private func fixtureFrame(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures/\(name)")
        return FakeServer.frame("message.created", try XCTUnwrap(ProtocolJSON.decode(Data(contentsOf: url))))
    }

    func testTheCacheIsShownAtLaunchWithoutTheNetwork() async throws {
        let before = await device()
        let (id, question) = try await conversation(on: before)
        let requests = server.requests.count

        let after = await device(cache: before.cache, vault: before.vault)
        let cached = await after.messages(id)
        XCTAssertEqual(cached, [question])
        let conversations = await after.engine.conversations()
        XCTAssertEqual(conversations.map(\.id), [id])
        let loggedIn = await after.engine.isLoggedIn
        XCTAssertTrue(loggedIn, "the session comes from the Keychain")
        XCTAssertEqual(server.requests.count, requests)
    }

    func testConfigIsKeptAndCheckedWithItsETag() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let config = await phone.engine.refreshConfig(language: "az")
        XCTAssertEqual(config?.brand.name, "Apar")
        XCTAssertEqual(config?.limits.textChars, 50)
        await phone.engine.refreshConfig()
        XCTAssertEqual(server.requests("GET", "/mobile/config").last?.headers["If-None-Match"], server.configETag)
        XCTAssertEqual(server.requests("GET", "/mobile/config").last?.url.query, "lang=az",
                       "a refresh asks for the language the texts are in")

        let relaunched = await device(cache: phone.cache, vault: phone.vault)
        let cached = await relaunched.engine.config
        XCTAssertEqual(cached, config)
        await relaunched.engine.refreshConfig(language: "ru")
        await relaunched.online()
        relaunched.socket.push(FakeServer.frame("config.changed", ["etag": "W/\"c2\"", "version": 13]))
        await expect { self.server.requests("GET", "/mobile/config").count == 4 }
        XCTAssertEqual(server.requests("GET", "/mobile/config").last?.url.query, "lang=ru",
                       "the refetch asks for the language the texts are in")
        XCTAssertTrue(phone.changes.all.contains(.config))
    }

    func testSocketEventsReachTheStore() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        // The list that `ready` fetches is the server's truth; the events below are newer than it.
        await expect { self.server.requests("GET", "/conversations").count == 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        let leyla: JSONValue = ["type": "operator", "name": "Leyla"]
        phone.socket.push(FakeServer.frame("conversation.updated", ["id": .string(id), "status": "open",
                                                                    "assignee": ["name": "Leyla"], "unread_count": 1]))
        phone.socket.push(FakeServer.frame("unread.changed", ["total": 3]))
        phone.socket.push(FakeServer.frame("read", ["conversation_id": .string(id), "up_to_seq": 1, "by": "user"]))
        phone.socket.push(FakeServer.frame("read", ["conversation_id": .string(id), "up_to_seq": 1, "by": "operator"]))
        phone.socket.push(FakeServer.frame("typing", ["conversation_id": .string(id), "sender": leyla, "state": "on"]))
        phone.socket.push(FakeServer.frame("conversation.rated", ["id": .string(id)]))
        await expect { phone.changes.all.contains { if case .typing = $0 { return true }; return false } }
        let unread = await phone.engine.unreadTotal
        XCTAssertEqual(unread, 3)
        let conversation = await phone.engine.conversations().first
        XCTAssertEqual(conversation?.status, .open)
        XCTAssertEqual(conversation?.assignee?.name, "Leyla")
        let read = await phone.engine.readByOperator(in: id)
        XCTAssertEqual(read, 1)
        let changes = phone.changes.all
        XCTAssertTrue(changes.contains(.unread(total: 3)))
        XCTAssertTrue(changes.contains(.read(conversationId: id, upToSeq: 1)))
        XCTAssertTrue(changes.contains(.typing(conversationId: id, sender: Sender(type: .operator, name: "Leyla"),
                                               isTyping: true)))
        XCTAssertEqual(changes.filter { $0 == .read(conversationId: id, upToSeq: 1) }.count, 1, "the user's own read is not news")
    }

    /// A bot's or operator's message over the socket, a copy too, tells the screen its sender stopped typing; the
    /// user's own does not, nor an update.
    func testAMessageOverTheSocketEndsItsSendersTyping() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()
        func arrivals() -> Int {
            phone.changes.all.filter { if case .arrived(id, let sender) = $0 { return sender.type == .bot }; return false }.count
        }
        let message = server.botSays("Bir", in: id)
        await expect { arrivals() == 1 }
        phone.socket.push(FakeServer.frame("message.created", message))
        await expect { arrivals() == 2 }
        phone.socket.push(FakeServer.frame("message.updated", message))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(arrivals(), 2, "an update is not a new message")
        XCTAssertFalse(phone.changes.all.contains { if case .arrived(_, let sender) = $0 { return sender.type == .user }; return false })
    }

    func testARefusedMessageFailsAtOnceWithTheServersReason() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        server.inject(.status(400, code: "validation_failed", fields: ["text": "too long"]), "POST", "/messages")
        let pending = try await phone.engine.sendText("Salam", in: id)
        await expect { await phone.pending(id).first?.state == .failed }
        let failed = await phone.pending(id).first
        XCTAssertEqual(failed?.attempts, 0)
        XCTAssertEqual(failed?.errorCode, "validation_failed")
        XCTAssertEqual(failed?.fields, ["text": "too long"])
        await phone.engine.discard(pending.id)
        let left = await phone.pending(id)
        XCTAssertTrue(left.isEmpty)
    }

    func testTheSocketClosesInTheBackgroundAndReopensInTheForeground() async throws {
        let phone = await device()
        _ = try await conversation(on: phone)
        await phone.online()
        await phone.engine.applicationDidEnterBackground()
        XCTAssertNil(phone.socket.live)
        time.advance(by: 60)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(phone.socket.connections.count, 1, "no reconnect in the background")
        await phone.engine.applicationWillEnterForeground()
        await expect { phone.socket.connections.count == 2 }
        await phone.engine.disconnect()
        await phone.engine.applicationWillEnterForeground()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(phone.socket.connections.count, 2, "disconnected stays disconnected")
    }

    func testReadAndTypingAreSentSparingly() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.engine.markRead(in: id)
        await phone.engine.markRead(in: id)
        XCTAssertEqual(server.requests("POST", "/read").count, 1)
        XCTAssertEqual(body(server.requests("POST", "/read").first), ["up_to_seq": 1])
        await phone.engine.markRead(in: "conv_unknown")

        await phone.engine.setTyping(true, in: id)
        await phone.engine.setTyping(true, in: id)
        XCTAssertEqual(server.requests("POST", "/typing").count, 1)
        time.advance(by: 3)
        await phone.engine.setTyping(true, in: id)
        await phone.engine.setTyping(false, in: id)
        await phone.engine.setTyping(false, in: id)
        XCTAssertEqual(server.requests("POST", "/typing").compactMap { self.body($0)?["state"]?.stringValue }, ["on", "on", "off"])
    }

    func testAFlowStartedByTheApp() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let started = try await phone.engine.startFlow("payment_failed", data: ["order_id": "A-1042"], openMessenger: true,
                                                       openedFrom: "checkout")
        XCTAssertEqual(body(server.requests("POST", "/flows/trigger").last)?["opened_from"], "checkout")
        let id = try XCTUnwrap(started?.id)
        let messages = await phone.messages(id)
        XCTAssertEqual(messages.count, 1)
        let nothing = try await phone.engine.startFlow("not_bound", data: [:], openMessenger: false)
        XCTAssertNil(nothing)
        try await phone.engine.track("ride_finished", data: ["minutes": 18])
        XCTAssertEqual(server.requests.last?.url.path, "/v1/events")
    }

    /// An app launch must not cost a login: the kept session serves the same person (brief 8 · 6.1).
    func testTheSamePersonKeepsTheSession() async throws {
        let first = await device()
        try await first.engine.loginUser(UserIdentity(userId: "7", name: "Aysel"), userHash: "hash_7")
        try await first.engine.loginUser(UserIdentity(userId: "7", name: "Aysel Məmmədova"), userHash: "hash_7")
        let relaunched = await device(cache: first.cache, vault: first.vault)
        try await relaunched.engine.loginUser(UserIdentity(userId: "7"), userHash: "hash_7")
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 1)
        let kept = try XCTUnwrap(first.vault.value(MobileSession.self, for: "session"))
        _ = try await relaunched.engine.startConversation(openedFrom: nil)
        XCTAssertEqual(server.requests("POST", "/conversations").last?.headers["Authorization"],
                       "Bearer \(kept.sessionToken)", "the relaunched app uses the kept token")

        let anonymous = await device()
        try await anonymous.engine.loginUnidentifiedUser()
        try await anonymous.engine.loginUnidentifiedUser()
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 2)
    }

    /// G6: the greeting's name is the logged-in user's. A new name on the same session says so with `.session`; a
    /// login without one keeps it; logout forgets it.
    func testTheLoggedInUsersNameIsKnown() async throws {
        let phone = await device()
        var name = await phone.engine.userName
        XCTAssertNil(name)
        try await phone.engine.loginUser(UserIdentity(userId: "5", email: "aysel@example.com", name: " Aysel "),
                                          userHash: nil)
        name = await phone.engine.userName
        XCTAssertEqual(name, "Aysel")
        let sessions = phone.changes.all.filter { $0 == .session }.count
        try await phone.engine.loginUser(UserIdentity(userId: "5", name: "Aysel Məmmədova"), userHash: nil)
        name = await phone.engine.userName
        XCTAssertEqual(name, "Aysel Məmmədova")
        XCTAssertEqual(phone.changes.all.filter { $0 == .session }.count, sessions + 1, "Home redraws the greeting")
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: nil)
        name = await phone.engine.userName
        XCTAssertEqual(name, "Aysel Məmmədova", "a login without a name keeps the one known")
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 1)
        await phone.engine.logout()
        name = await phone.engine.userName
        XCTAssertNil(name)
    }

    func testAnotherPersonGetsANewSession() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "1"), userHash: "hash_1")
        try await phone.engine.loginUser(UserIdentity(userId: "2"), userHash: "hash_2")
        try await phone.engine.loginUser(UserIdentity(userId: "2"), userHash: "other")
        try await phone.engine.loginUser(UserIdentity(email: "Aysel@Example.com "), userHash: nil)
        try await phone.engine.loginUser(UserIdentity(email: "aysel@example.com"), userHash: nil)
        try await phone.engine.loginUnidentifiedUser()
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 5, "same email, other case: same person")
        await phone.engine.logout()
        try await phone.engine.loginUnidentifiedUser()
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 6, "a new visitor after logout")
    }

    /// A kept session that expired is refreshed; one whose refresh token is refused is opened again.
    func testAnExpiredKeptSessionIsRenewed() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "3"), userHash: "hash_3")
        time.advance(by: 2 * 86_400)
        try await phone.engine.loginUser(UserIdentity(userId: "3"), userHash: "hash_3")
        XCTAssertEqual(server.requests("POST", "/mobile/sessions/refresh").count, 1)
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 1)

        time.advance(by: 2 * 86_400)
        server.revokeRefreshTokens()
        try await phone.engine.loginUser(UserIdentity(userId: "3"), userHash: "hash_3")
        XCTAssertEqual(server.requests("POST", "/mobile/sessions").count, 2)
    }

    func testSeveralScreensHearEveryChange() async throws {
        let phone = await device()
        let badge = Changes()
        let token = await phone.engine.observe { badge.append($0) }
        _ = try await conversation(on: phone)
        await phone.online()
        phone.socket.push(FakeServer.frame("unread.changed", ["total": 4]))
        await expect { badge.all.contains(.unread(total: 4)) && phone.changes.all.contains(.unread(total: 4)) }
        await phone.engine.stopObserving(token)
        phone.socket.push(FakeServer.frame("unread.changed", ["total": 5]))
        await expect { phone.changes.all.contains(.unread(total: 5)) }
        XCTAssertFalse(badge.all.contains(.unread(total: 5)), "stopped listening")
    }

    /// A file is kept on the device, uploaded, then sent as an attachment; the staged copy goes once the server has it.
    func testAFileIsUploadedThenSent() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        server.inject(.offline, "POST", "/uploads")
        let data = Data(repeating: 7, count: 2_000)
        let pending = try await phone.engine.sendFile(data, fileName: "velo.jpg", mime: "image/jpeg",
                                                      caption: "Velosiped", in: id)
        XCTAssertEqual(pending.upload?.fileName, "velo.jpg")
        XCTAssertEqual(pending.upload?.size, 2_000)
        let stored = await phone.engine.localFile(of: pending)
        let local = try XCTUnwrap(stored)
        XCTAssertEqual(try Data(contentsOf: local), data)

        let sent = await drive(time) { await phone.pending(id).isEmpty }
        XCTAssertTrue(sent)
        XCTAssertEqual(server.requests("POST", "/uploads").count, 2, "the upload is retried like a message")
        XCTAssertEqual(body(server.requests("POST", "/messages").last)?["content"],
                       ["upload_id": "upl_1", "caption": "Velosiped"])
        XCTAssertEqual(body(server.requests("POST", "/messages").last)?["client_id"]?.stringValue, pending.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        XCTAssertEqual(userMessages(id).count, 1)
    }

    /// Uploaded but not yet sent when the app closed: the next launch sends the message without uploading again.
    func testAnUploadedFileIsNotUploadedAgainAfterARestart() async throws {
        let frozen = TestTime()
        let before = await device(time: frozen)
        let (id, _) = try await conversation(on: before)
        server.inject(.offline, "POST", "/messages")
        let pending = try await before.engine.sendFile(Data("pdf".utf8), fileName: "qaime.pdf", mime: "application/pdf",
                                                       caption: nil, in: id)
        await expect { await before.pending(id).first?.attempts == 1 }
        let uploaded = await before.pending(id).first?.upload?.uploadId
        XCTAssertEqual(uploaded, "upl_1")

        let after = await device(cache: before.cache, vault: before.vault)
        let carried = await after.pending(id)
        XCTAssertEqual(carried.map(\.id), [pending.id])
        await after.engine.connect()
        await expect { await after.pending(id).isEmpty }
        XCTAssertEqual(server.requests("POST", "/uploads").count, 1)
        XCTAssertEqual(userMessages(id).count, 1)
    }

    func testFilesOverTheLimitAreRefused() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        do {
            try await phone.engine.sendFile(Data(count: 10 * 1_048_576 + 1), fileName: "big.jpg", mime: "image/jpeg",
                                            caption: nil, in: id)
            XCTFail("over the 10 MB image limit")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("file over 10 MB"))
        }
        let pdf = try await phone.engine.sendFile(Data(count: 12 * 1_048_576), fileName: "big.pdf",
                                                  mime: "application/pdf", caption: nil, in: id)
        XCTAssertEqual(pdf.upload?.mime, "application/pdf", "other files may be up to 25 MB")
        await phone.engine.discard(pdf.id)
        let stored = await phone.engine.localFile(of: pdf)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(stored).path), "discarding deletes it")
    }

    func testAConversationOpenedFromAPush() async throws {
        let other = await device()
        let (id, _) = try await conversation(on: other, user: "5")
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        let unknown = await phone.engine.conversation(id)
        XCTAssertNil(unknown)
        try await phone.engine.refreshConversation(id)
        let known = await phone.engine.conversation(id)
        XCTAssertEqual(known?.status, .bot)
    }

    func testUserAndUploadPassThrough() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let user = try await phone.engine.updateUser(["name": "Aysel"])
        XCTAssertEqual(user.name, "Aysel")
        let upload = try await phone.engine.upload(Data([1, 2, 3]), fileName: "a.jpg", mime: "image/jpeg")
        XCTAssertEqual(upload.size, Int(server.requests.last?.body?.count ?? 0))
    }

    func testADisabledAppIsNoted() async throws {
        let phone = await device()
        server.inject(.status(403, code: "app_disabled"), "POST", "/mobile/sessions")
        do {
            try await phone.engine.loginUnidentifiedUser()
            XCTFail("expected app_disabled")
        } catch {
            XCTAssertEqual((error as? ClomniError)?.code, "app_disabled")
        }
        let disabled = await phone.engine.isAppDisabled
        XCTAssertTrue(disabled)
        try await phone.engine.loginUnidentifiedUser()
        let enabled = await phone.engine.isAppDisabled
        XCTAssertFalse(enabled)
    }

    func testFormRatingBackAndAttachmentPayloads() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        await phone.online()

        // Back: only under quick replies that offer it.
        let step = server.botAsks("Seçin", buttons: ["A"], in: id)
        await expect { await phone.messages(id).count == 2 }
        let newest = await phone.engine.messages(in: id).last
        let stepMessage = try XCTUnwrap(newest)
        XCTAssertEqual(stepMessage.id, step["id"]?.stringValue)
        let back = try await phone.engine.goBack(from: stepMessage)
        XCTAssertNil(back.preview)
        XCTAssertEqual(back.message.content, .buttonReply(replyTo: stepMessage.id, buttonId: "back", payload: "nav:back"))
        await expect { await phone.pending(id).isEmpty }
        let backReply = await phone.messages(id).last?.content
        XCTAssertEqual(backReply, .text("← Geri"))

        // A form and a rating of another conversation (conv_5521, unknown to the server: 404 fails them at once).
        phone.socket.push(try fixtureFrame("19-form-contact.json"))
        phone.socket.push(try fixtureFrame("28-rating.json"))
        await expect { await phone.messages("conv_5521").count == 2 }
        let stored = await phone.messages("conv_5521")
        let form = try XCTUnwrap(stored.first { $0.type == "form" })
        let rating = try XCTUnwrap(stored.first { $0.type == "rating" })
        do {
            try await phone.engine.goBack(from: form)
            XCTFail("a form has no back button")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("no back button"))
        }
        try await phone.engine.submitForm(form, values: ["name": "Aysel", "phone": "+994501234567"])
        await expect { await phone.pending("conv_5521").first?.state == .failed }
        let failedForm = await phone.pending("conv_5521").first
        XCTAssertEqual(failedForm?.errorCode, "conversation_not_found")
        XCTAssertEqual(body(server.requests("POST", "/messages").last)?["content"],
                       ["reply_to": "msg_f19", "form_id": "frm_contact",
                        "values": ["name": "Aysel", "phone": "+994501234567"]])
        do {
            try await phone.engine.submitForm(rating, values: [:])
            XCTFail("not a form")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("not a form"))
        }

        do {
            try await phone.engine.submitRating(rating, score: 6, comment: nil)
            XCTFail("scores are 1 to 5")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("rating not open"))
        }
        try await phone.engine.submitRating(rating, score: 5, comment: "Tez cavab verdiniz")
        do {
            try await phone.engine.submitRating(rating, score: 4, comment: nil)
            XCTFail("rated already")
        } catch {
            XCTAssertEqual(error as? ClomniError, .rejected("rating not open"))
        }
        await expect { await phone.pending("conv_5521").count == 2 && phone.changes.all.count > 0 }
        await expect { self.server.requests("POST", "/messages").count == 3 }
        XCTAssertEqual(body(server.requests("POST", "/messages").last)?["content"],
                       ["reply_to": "msg_f28", "score": 5, "comment": "Tez cavab verdiniz"])

        let attachment = await phone.engine.sendAttachment(uploadId: "upl_77ab", caption: "Velosiped", in: id)
        XCTAssertEqual(attachment.preview, "Velosiped")
        await expect { await phone.pending(id).isEmpty }
        XCTAssertEqual(body(server.requests("POST", "/messages").last)?["content"],
                       ["upload_id": "upl_77ab", "caption": "Velosiped"])
    }

    func testHistoryPagesBack() async throws {
        let phone = await device()
        let (id, _) = try await conversation(on: phone)
        for index in 1...60 { server.botSays("\(index)", in: id, silently: true) }
        let fresh = await device(vault: phone.vault)
        try await fresh.engine.loadMessages(in: id)
        let latest = await fresh.messages(id)
        XCTAssertEqual(latest.map(\.seq), Array(12...61))
        let more = try await fresh.engine.loadOlder(in: id)
        XCTAssertFalse(more)
        let all = await fresh.messages(id)
        XCTAssertEqual(all.map(\.seq), Array(1...61))
        let none = try await fresh.engine.loadOlder(in: id)
        XCTAssertFalse(none, "seq 1 is the beginning")

        // Loading again only asks for what is newer.
        server.botSays("62", in: id, silently: true)
        try await fresh.engine.loadMessages(in: id)
        XCTAssertEqual(server.requests("GET", "/messages").last?.url.query, "after_seq=61&limit=100")
        let empty = await device(vault: phone.vault)
        let loaded = try await empty.engine.loadOlder(in: id)
        XCTAssertTrue(loaded, "with nothing cached, the latest page")
    }
}
