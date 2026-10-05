import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

final class MessageStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_850_600)

    private func message(_ id: String, seq: Int, in conversation: String = "conv_1", interactive: Bool? = nil,
                         text: String = "x", clientId: String? = nil) -> Message {
        Message(id: id, clientId: clientId, conversationId: conversation, type: "text", sender: Sender(type: .bot),
                createdAt: start.addingTimeInterval(Double(seq)), seq: seq, lang: "az",
                flow: interactive.map { FlowRef(flowId: "flw_1", nodeId: "N", interactive: $0) }, content: .text(text),
                fallbackText: text)
    }

    private func conversation(_ id: String, last: Message? = nil, created: Double = 0) -> Conversation {
        var json: JSONValue = ["id": .string(id), "status": "bot", "unread_count": 2,
                               "created_at": .string(start.addingTimeInterval(created).formatted(.iso8601))]
        if case .object(var fields) = json, let last {
            fields["last_message"] = try? ProtocolJSON.decode(JSONEncoder().encode(last))
            json = .object(fields)
        }
        return ProtocolJSON.parseConversation(ProtocolJSON.encode(json))!
    }

    func testAMessageIsKeptOnceInSeqOrder() {
        var store = MessageStore()
        store.insert(message("msg_3", seq: 3))
        store.insert(message("msg_1", seq: 1))
        store.insert(message("msg_2", seq: 2))
        // The same message over REST and over the socket.
        store.insert(message("msg_2", seq: 2))
        XCTAssertEqual(store.messages(in: "conv_1").map(\.id), ["msg_1", "msg_2", "msg_3"])
        XCTAssertEqual(store.lastSeq(in: "conv_1"), 3)
        XCTAssertNil(store.lastSeq(in: "conv_none"))
        XCTAssertEqual(store.message("msg_2", in: "conv_1")?.seq, 2)
    }

    func testACopyUnderAnotherIdReplacesTheMessageOfItsSeq() {
        var store = MessageStore()
        store.insert(message("msg_1", seq: 1))
        store.insert(message("msg_2", seq: 2, text: "first"))
        store.insert(message("msg_2b", seq: 2, text: "again"), detectGap: true)
        XCTAssertEqual(store.messages(in: "conv_1").map(\.id), ["msg_1", "msg_2b"])
        XCTAssertEqual(store.messages(in: "conv_1").map(\.content), [.text("x"), .text("again")])
        // The reopen cursor is the highest seq received, past a hole the user never sees: the flow's answers that
        // came over the socket are not asked for again.
        XCTAssertEqual(store.insert(message("msg_5", seq: 5), detectGap: true), 2)
        XCTAssertEqual(store.lastSeq(in: "conv_1"), 5)
    }

    func testAnUpdateReplacesTheMessage() {
        var store = MessageStore()
        store.insert(message("msg_1", seq: 1, interactive: true, text: "before"))
        store.insert(message("msg_1", seq: 1, interactive: false, text: "after"))
        XCTAssertEqual(store.messages(in: "conv_1").map(\.content), [.text("after")])
    }

    func testASkippedSeqIsAGap() {
        var store = MessageStore()
        XCTAssertNil(store.insert(message("msg_40", seq: 40), detectGap: true), "nothing known yet: history, not a gap")
        XCTAssertNil(store.insert(message("msg_41", seq: 41), detectGap: true))
        XCTAssertEqual(store.insert(message("msg_43", seq: 43), detectGap: true), 41)
        XCTAssertEqual(store.firstGap(in: "conv_1"), 41)
        XCTAssertNil(store.insert(message("msg_42", seq: 42), detectGap: true), "a late message fills the hole")
        XCTAssertNil(store.firstGap(in: "conv_1"))
        XCTAssertNil(store.insert(message("msg_50", seq: 50)), "REST pages are not checked")
    }

    func testOnlyTheLatestUnansweredInteractiveMessageCanBeAnswered() {
        var store = MessageStore()
        let first = message("msg_1", seq: 1, interactive: true)
        let second = message("msg_2", seq: 2, interactive: true)
        store.insert(first)
        XCTAssertTrue(store.canAnswer(first))
        store.insert(second)
        store.insert(message("msg_3", seq: 3, interactive: nil))
        XCTAssertFalse(store.canAnswer(first), "an older step")
        XCTAssertTrue(store.canAnswer(second), "a plain message after it does not end it")
        store.markAnswered("msg_2")
        XCTAssertFalse(store.canAnswer(second))
        XCTAssertFalse(store.canAnswer(message("msg_9", seq: 9, interactive: false)))
        XCTAssertTrue(store.canAnswer(message("msg_7", seq: 7, in: "conv_other", interactive: true)), "not stored yet")
    }

    func testTheOtherDevicesAnswerDisablesTheButtons() {
        var store = MessageStore()
        store.insert(message("msg_1", seq: 1, interactive: true))
        // message.updated from the server after the other device answered.
        store.insert(message("msg_1", seq: 1, interactive: false))
        XCTAssertFalse(store.canAnswer(store.messages(in: "conv_1")[0]))
    }

    func testConversations() {
        var store = MessageStore()
        store.upsert(conversation("conv_1", created: -20))
        store.upsert(conversation("conv_2", created: -10))
        XCTAssertEqual(store.sortedConversations.map(\.id), ["conv_2", "conv_1"])

        // A message makes its conversation the newest and its last message.
        store.insert(message("msg_5", seq: 5, in: "conv_1"))
        XCTAssertEqual(store.sortedConversations.map(\.id), ["conv_1", "conv_2"])
        XCTAssertEqual(store.conversations["conv_1"]?.lastMessage?.id, "msg_5")

        // A list fetched before that message must not take it back.
        store.upsert(conversation("conv_1", last: message("msg_4", seq: 4, in: "conv_1"), created: -20))
        XCTAssertEqual(store.conversations["conv_1"]?.lastMessage?.id, "msg_5")
        store.upsert(conversation("conv_1", last: message("msg_6", seq: 6, in: "conv_1"), created: -20))
        XCTAssertEqual(store.conversations["conv_1"]?.lastMessage?.id, "msg_6")

        let update = ProtocolJSON.parseEvent(FakeServer.frame("conversation.updated", [
            "id": "conv_1", "status": "open", "assignee": ["name": "Leyla"], "unread_count": 3]))
        guard case .conversationUpdated(let change)? = update?.data else { return XCTFail() }
        store.apply(change)
        XCTAssertEqual(store.conversations["conv_1"]?.status, .open)
        XCTAssertEqual(store.conversations["conv_1"]?.assignee?.name, "Leyla")
        XCTAssertEqual(store.conversations["conv_1"]?.unreadCount, 3)
        store.markSeen("conv_1")
        XCTAssertEqual(store.conversations["conv_1"]?.unreadCount, 0)

        let unknown = ProtocolJSON.parseEvent(FakeServer.frame("conversation.updated", ["id": "conv_9", "status": "open"]))
        guard case .conversationUpdated(let other)? = unknown?.data else { return XCTFail() }
        store.apply(other)
        XCTAssertNil(store.conversations["conv_9"])
    }

    func testReadMarkerOnlyMovesForward() {
        var store = MessageStore()
        store.markReadByOperator("conv_1", upToSeq: 5)
        store.markReadByOperator("conv_1", upToSeq: 3)
        XCTAssertEqual(store.readUpTo["conv_1"], 5)
    }

    func testDiskCopyKeepsTheNewestMessagesAndReadsBack() throws {
        var store = MessageStore()
        store.upsert(conversation("conv_1"))
        for seq in 1...5 { store.insert(message("msg_\(seq)", seq: seq)) }
        store.markAnswered("msg_2")
        store.unreadTotal = 4
        let disk = store.trimmed(to: 3)
        XCTAssertEqual(disk.messages(in: "conv_1").map(\.seq), [3, 4, 5])
        let read = try JSONDecoder().decode(MessageStore.self, from: JSONEncoder().encode(disk))
        XCTAssertEqual(read, disk)
        XCTAssertEqual(read.unreadTotal, 4)
        XCTAssertTrue(read.answered.contains("msg_2"))
    }

    func testOutbox() throws {
        var outbox = Outbox()
        let first = PendingMessage(conversationId: "conv_1", message: ClientMessage(content: .text("a")), preview: "a",
                                   createdAt: start)
        let second = PendingMessage(conversationId: "conv_2", message: ClientMessage(content: .text("b")), preview: "b",
                                    createdAt: start)
        outbox.add(first)
        outbox.add(second)
        XCTAssertEqual(outbox.next?.id, first.id)
        outbox.update(first.id) { $0.state = .failed }
        XCTAssertEqual(outbox.next?.id, second.id, "a failed message waits for the user")
        XCTAssertEqual(outbox.entries(in: "conv_1").map(\.state), [.failed])
        XCTAssertEqual(try JSONDecoder().decode(Outbox.self, from: JSONEncoder().encode(outbox)), outbox)
        XCTAssertEqual(outbox.remove(second.id)?.preview, "b")
        XCTAssertNil(outbox.remove(second.id))
        outbox.update("missing") { $0.attempts = 9 }
        XCTAssertNil(outbox.next)
    }

    func testDiskCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clomni-\(UUID().uuidString)")
        let cache = DiskCache(directory: directory)
        XCTAssertNil(cache.read("a.json"))
        cache.save(["x": 1], "a.json")
        XCTAssertEqual(cache.load([String: Int].self, "a.json"), ["x": 1])
        cache.write(nil, "a.json")
        XCTAssertNil(cache.read("a.json"))
        cache.write(Data("{".utf8), "b.json")
        XCTAssertNil(cache.load([String: Int].self, "b.json"))
        cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(DiskCache.standard(appId: "app_1").directory.path.hasSuffix("Clomni/app_1"))
    }
}
