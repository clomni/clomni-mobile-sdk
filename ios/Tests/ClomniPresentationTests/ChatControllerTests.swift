import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore
@testable import ClomniPresentation

/// A conversation the test fills in, recording what the controller asked for.
actor FakeChat: ChatDataSource {
    var cachedConfig: MessengerConfig? = Fixture.aparConfig
    var conversations: [String: Conversation] = [:]
    var stored: [String: [Message]] = [:]
    var outbox: [PendingMessage] = []
    var answerable: Set<String> = []
    var loadFails = false
    var calls: [String] = []
    var typingStates: [Bool] = []
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]

    var observerCount: Int { observers.count }
    var config: MessengerConfig? { cachedConfig }

    func set(_ messages: [Message], in id: String = "conv_5521", answerable: Set<String> = [], loadFails: Bool = false) {
        stored[id] = messages
        self.answerable = answerable
        self.loadFails = loadFails
    }

    func push(_ change: ClomniChange) {
        observers.values.forEach { $0(change) }
    }

    func conversation(_ id: String) -> Conversation? { conversations[id] }

    func refreshConversation(_ id: String) async throws {
        calls.append("refreshConversation \(id)")
        conversations[id] = Fixture.conversation(status: "bot")
    }

    func messages(in conversationId: String) -> [Message] { stored[conversationId] ?? [] }
    func pending(in conversationId: String) -> [PendingMessage] { outbox.filter { $0.conversationId == conversationId } }
    func canAnswer(_ message: Message) -> Bool { answerable.contains(message.id) }
    func readByOperator(in conversationId: String) -> Int? { nil }

    func localFile(of pending: PendingMessage) -> URL? {
        pending.upload.map { URL(fileURLWithPath: "/tmp/\($0.storedAs)") }
    }

    func loadMessages(in conversationId: String) async throws {
        calls.append("load \(conversationId)")
        if loadFails { throw ClomniError.network("offline") }
    }

    func loadOlder(in conversationId: String) async throws -> Bool {
        calls.append("older \(conversationId)")
        return false
    }

    func markRead(in conversationId: String) { calls.append("read \(conversationId)") }
    func setTyping(_ isTyping: Bool, in conversationId: String) { typingStates.append(isTyping) }

    func sendText(_ text: String, in conversationId: String) throws -> PendingMessage {
        calls.append("text \(text)")
        return queue(.text(text), in: conversationId, preview: text)
    }

    func reply(to message: Message, with button: MessageContent.Button) throws -> PendingMessage {
        guard answerable.remove(message.id) != nil else { throw ClomniError.rejected("already answered") }
        calls.append("reply \(message.id) \(button.id)")
        return queue(.buttonReply(replyTo: message.id, buttonId: button.id, payload: button.payload),
                     in: message.conversationId, preview: button.title)
    }

    func goBack(from message: Message) throws -> PendingMessage {
        calls.append("back \(message.id)")
        return queue(.back(replyTo: message.id), in: message.conversationId, preview: nil)
    }

    func submitForm(_ message: Message, values: [String: JSONValue]) throws -> PendingMessage {
        calls.append("form \(message.id) \(String(decoding: ProtocolJSON.encode(.object(values)), as: UTF8.self))")
        return queue(.formSubmit(replyTo: message.id, formId: "frm", values: values), in: message.conversationId,
                     preview: nil)
    }

    func sendFile(_ data: Data, fileName: String, mime: String, caption: String?,
                  in conversationId: String) throws -> PendingMessage {
        guard data.count <= 10 else { throw ClomniError.rejected("file over 10 MB") }
        calls.append("file \(fileName)")
        var entry = queue(.attachment(uploadId: "", caption: caption), in: conversationId, preview: caption)
        entry.upload = PendingUpload(fileName: fileName, mime: mime, size: data.count, storedAs: "upload-1")
        outbox[outbox.count - 1] = entry
        return entry
    }

    func retry(_ clientId: String) throws { calls.append("retry \(clientId)") }

    func draftConversation(openedFrom: String?) async -> String {
        calls.append("draft")
        return "draft_1"
    }

    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func stopObserving(_ token: UUID) { observers[token] = nil }

    private func queue(_ content: ClientMessage.Content, in conversationId: String, preview: String?) -> PendingMessage {
        let entry = PendingMessage(conversationId: conversationId, message: ClientMessage(content: content),
                                   preview: preview, createdAt: Date(timeIntervalSince1970: 1_790_850_700))
        outbox.append(entry)
        return entry
    }
}

@MainActor
final class ChatControllerTests: XCTestCase {
    private let source = FakeChat()
    private var renders = 0

    private let timer = ManualTimer()

    private func controller() -> ChatController {
        let timer = timer
        let chat = ChatController(source: source, conversationId: "conv_5521", language: "az",
                                  known: ["name": "Aysel"], timeZone: TimeZone(identifier: "UTC")!,
                                  now: { Date(timeIntervalSince1970: 1_790_850_720) },
                                  sleep: { try await timer.sleep($0) })
        chat.onChange = { [weak self] in self?.renders += 1 }
        return chat
    }

    private func calls() async -> [String] { await source.calls }

    func testLoadsCacheThenServerAndMarksRead() async {
        await source.set([Fixture.message("01-text-bot.json")])
        let chat = controller()
        XCTAssertEqual(chat.screen.phase, .loading)
        await chat.load()
        XCTAssertEqual(chat.screen.phase, .ready)
        XCTAssertEqual(renders, 2)
        let made = await calls()
        XCTAssertEqual(made, ["refreshConversation conv_5521", "load conv_5521", "read conv_5521"])
        XCTAssertEqual(chat.screen.header.title, "Apar")
        XCTAssertEqual(chat.config?.brand.name, "Apar")
        await chat.load()
        let observers = await source.observerCount
        XCTAssertEqual(observers, 1)
    }

    func testFailedFirstLoadOffersRetry() async {
        await source.set([], loadFails: true)
        let chat = controller()
        await chat.load()
        XCTAssertEqual(chat.screen.phase, .failed)
        await source.set([Fixture.message("01-text-bot.json")])
        await chat.retry()
        XCTAssertEqual(chat.screen.phase, .ready)
    }

    func testButtonsBackAndASecondTap() async {
        let step = Fixture.message("10-apar-level2-S-chips.json")
        await source.set([step], answerable: [step.id])
        let chat = controller()
        await chat.load()
        XCTAssertEqual(chat.screen.composer.mode, .hidden)
        await chat.tap("o_t", in: step.id)
        await chat.tap("o_u", in: step.id)
        await chat.tap("missing", in: "msg_unknown")
        var made = await calls()
        XCTAssertEqual(made.filter { $0.hasPrefix("reply") }, ["reply msg_f10 o_t"], "the second tap finds the buttons gone")
        XCTAssertFalse(chat.screen.items.contains { if case .replies = $0 { return true }; return false })
        XCTAssertTrue(chat.screen.items.contains {
            if case .bubble(let bubble) = $0, case .text(let runs) = bubble.body { return runs.first?.text == "Velosiped dayandı" }
            return false
        }, "the choice stays as the user's message")
        await source.set([step], answerable: [step.id])
        await chat.tap("back", in: step.id)
        made = await calls()
        XCTAssertTrue(made.contains("back msg_f10"))
    }

    func testFormErrorsThenSubmit() async {
        let form = Fixture.message("19-form-contact.json")
        await source.set([form], answerable: [form.id])
        let chat = controller()
        await chat.load()
        let errors = await chat.submit(form.id, values: ["name": "", "phone": "12"])
        XCTAssertEqual(errors, ["name": "Bu sahəni doldurun", "phone": "Telefon nömrəsi düzgün deyil"])
        var made = await calls()
        XCTAssertFalse(made.contains { $0.hasPrefix("form") })
        let none = await chat.submit(form.id, values: ["name": "Aysel", "phone": "050 123 45 67"])
        XCTAssertEqual(none, [:])
        made = await calls()
        XCTAssertTrue(made.contains(#"form msg_f19 {"email":"","name":"Aysel","phone":"+994501234567"}"#), "\(made)")
        let notAForm = await chat.submit("msg_unknown", values: [:])
        XCTAssertEqual(notAForm, [:])
    }

    func testSendingTextFilesAndRetry() async {
        let chat = controller()
        await chat.load()
        let blank = await chat.send("   ")
        XCTAssertFalse(blank)
        let sent = await chat.send("Salam")
        XCTAssertTrue(sent)
        await chat.textChanged("Sa")
        await chat.textChanged("  ")
        let typing = await source.typingStates
        XCTAssertEqual(typing, [false, true, false], "off after sending, on while typing, off when cleared")

        let tooBig = await chat.sendFile(Data(count: 20), fileName: "big.jpg", mime: "image/jpeg")
        XCTAssertEqual(tooBig, "Fayl çox böyükdür (maks. 10 MB)")
        let fine = await chat.sendFile(Data(count: 5), fileName: "velo.jpg", mime: "image/jpeg", caption: "Velosiped")
        XCTAssertNil(fine)
        await source.push(.messages(conversationId: "conv_5521"))
        await chat.settled()
        let images = chat.screen.items.compactMap { item -> URL? in
            if case .bubble(let bubble) = item, case .image(let image) = bubble.body { return image.localFile }
            return nil
        }
        XCTAssertEqual(images, [URL(fileURLWithPath: "/tmp/upload-1")])
        await chat.retrySending("abc")
        let made = await calls()
        XCTAssertEqual(made.filter { !$0.hasPrefix("load") && !$0.hasPrefix("read") && !$0.hasPrefix("refresh") },
                       ["text Salam", "file velo.jpg", "retry abc"])
    }

    func testTypingShowsAndHides() async throws {
        await source.set([Fixture.message("03-text-user.json")])
        let chat = controller()
        await chat.load()
        let leyla = Sender(type: .operator, name: "Leyla")
        await source.push(.typing(conversationId: "conv_5521", sender: leyla, isTyping: true))
        await source.push(.typing(conversationId: "conv_other", sender: leyla, isTyping: true))
        await chat.settled()
        guard case .typing? = chat.screen.items.last else { return XCTFail("typing shows") }
        // The timeout passes (on the test's clock).
        await timer.waitForSleepers(1)
        await timer.fire()
        await chat.typingHide?.value
        if case .typing? = chat.screen.items.last { XCTFail("hidden after the timeout") }

        // A message from the one typing ends it at once.
        await source.push(.typing(conversationId: "conv_5521", sender: leyla, isTyping: true))
        await chat.settled()
        guard case .typing? = chat.screen.items.last else { return XCTFail("typing shows again") }
        await source.set([Fixture.message("03-text-user.json"),
                          Fixture.message("31-operator-no-avatar.json", ["created_at": "2026-10-01T10:31:00Z"])])
        await source.push(.messages(conversationId: "conv_5521"))
        await chat.settled()
        if case .typing? = chat.screen.items.last { XCTFail("the message replaced the indicator") }

        await source.push(.typing(conversationId: "conv_5521", sender: leyla, isTyping: true))
        await source.push(.typing(conversationId: "conv_5521", sender: leyla, isTyping: false))
        await chat.settled()
        if case .typing? = chat.screen.items.last { XCTFail("off is off") }
    }

    func testOtherChangesAndStop() async throws {
        let chat = controller()
        await chat.load()
        let before = renders
        await source.push(.unread(total: 3))
        await source.push(.messages(conversationId: "conv_other"))
        await chat.settled()
        XCTAssertEqual(renders, before, "not this conversation's business")
        await source.push(.read(conversationId: "conv_5521", upToSeq: 3))
        await source.push(.conversations)
        await chat.settled()
        XCTAssertEqual(renders, before + 2)
        chat.isOffline = true
        XCTAssertEqual(chat.screen.offline, "İnternet yoxdur")
        let more = await chat.loadOlder()
        XCTAssertFalse(more)
        await chat.stop()
        let observers = await source.observerCount
        XCTAssertEqual(observers, 0)
        let typing = await source.typingStates
        XCTAssertEqual(typing.last, false)
    }

    func testStartingANewConversationInPlace() async {
        await source.set([Fixture.message("24-system-conversation-closed.json")])
        let chat = controller()
        await chat.load()
        await chat.startNewConversation()
        XCTAssertEqual(chat.conversationId, "draft_1", "a draft until its first message")
        var made = await calls()
        XCTAssertTrue(made.contains("draft"))
        XCTAssertTrue(chat.screen.items.isEmpty)

        // The first message made the server create it: the screen follows the conversation's id.
        await source.push(.conversationCreated(draft: "draft_1", conversationId: "conv_new"))
        await chat.settled()
        XCTAssertEqual(chat.conversationId, "conv_new")
        await source.push(.conversationCreated(draft: "draft_9", conversationId: "conv_other"))
        await chat.settled()
        XCTAssertEqual(chat.conversationId, "conv_new", "another draft's")
        made = await calls()
        XCTAssertFalse(made.contains("start"))
    }

    func testTheEngineIsAChatSource() {
        let engine: ChatDataSource = ClomniEngine(appId: "app_test", apiKey: "ios_sdk-test")
        XCTAssertNotNil(engine)
    }
}

/// The typing timeout's clock in tests: a sleep lasts until `fire`, not for real seconds.
actor ManualTimer {
    private var sleepers: [CheckedContinuation<Void, Error>] = []
    private var arrivals: [(count: Int, waiter: CheckedContinuation<Void, Never>)] = []

    func sleep(_ seconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (sleeper: CheckedContinuation<Void, Error>) in
            sleepers.append(sleeper)
            let ready = arrivals.filter { $0.count <= sleepers.count }
            arrivals.removeAll { $0.count <= sleepers.count }
            ready.forEach { $0.waiter.resume() }
        }
    }

    /// Until `count` sleeps are waiting.
    func waitForSleepers(_ count: Int) async {
        guard sleepers.count < count else { return }
        await withCheckedContinuation { arrivals.append((count, $0)) }
    }

    /// Every waiting sleep ends.
    func fire() {
        let waking = sleepers
        sleepers = []
        waking.forEach { $0.resume() }
    }
}
