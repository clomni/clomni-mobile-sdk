import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// What the conversation screen reads and does; `ClomniEngine` is one, tests use a fake.
package protocol ChatDataSource: Sendable {
    var config: MessengerConfig? { get async }
    /// The socket is connected and delivering: no need to ask for new messages by hand.
    var isLive: Bool { get async }
    func conversation(_ id: String) async -> Conversation?
    func refreshConversation(_ id: String) async throws
    func messages(in conversationId: String) async -> [Message]
    func pending(in conversationId: String) async -> [PendingMessage]
    func canAnswer(_ message: Message) async -> Bool
    func readByOperator(in conversationId: String) async -> Int?
    func localFile(of pending: PendingMessage) async -> URL?
    func loadMessages(in conversationId: String) async throws
    func loadOlder(in conversationId: String) async throws -> Bool
    func markRead(in conversationId: String) async
    func setTyping(_ isTyping: Bool, in conversationId: String) async
    func sendText(_ text: String, in conversationId: String, replyTo: String?) async throws -> PendingMessage
    func reply(to message: Message, with button: MessageContent.Button) async throws -> PendingMessage
    func goBack(from message: Message) async throws -> PendingMessage
    func submitForm(_ message: Message, values: [String: JSONValue]) async throws -> PendingMessage
    func submitRating(_ message: Message, score: Int, comment: String?) async throws -> PendingMessage
    /// `voice`: a voice message's length and waveform, as recorded (CM-130).
    func sendFile(_ data: Data, fileName: String, mime: String, caption: String?,
                  in conversationId: String, replyTo: String?, voice: ClientMessage.Voice?) async throws -> PendingMessage
    func retry(_ clientId: String) async throws
    func draftConversation(openedFrom: String?) async -> String
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID
    func stopObserving(_ token: UUID) async
}

extension ClomniEngine: ChatDataSource {}

/// Keeps one conversation's screen current and turns taps into engine calls. The SwiftUI view observes it through
/// `onChange`.
/// A short sound of the conversation (DESIGN-PASS-3 A7): a message from the other side, or one the user sent.
package enum ChatSound: Sendable {
    case incoming, sent
}

@MainActor
package final class ChatController {
    package private(set) var screen: ChatScreen
    /// Called after `screen` changed.
    package var onChange: (() -> Void)?
    /// Plays a short sound (DESIGN-PASS-3 A7); called only while the panel allows sounds (`sounds`).
    package var playSound: ((ChatSound) -> Void)?
    /// Changes when "Yeni söhbət başlat" opens a new conversation in place of a closed one, and when the server
    /// creates a draft with its first message.
    package private(set) var conversationId: String

    package var isOffline = false {
        didSet { render() }
    }

    /// For the theme: the brand's colours and appearance.
    package var config: MessengerConfig? { snapshot.config }

    private let source: ChatDataSource
    private let language: String?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let typingTimeout: TimeInterval
    /// A message newer than this that arrives while the screen is open gets the incoming sound.
    private let openedAt: Date
    private var snapshot: ChatSnapshot
    private var observation: UUID?
    private lazy var changes = ChangeQueue { [weak self] change in await self?.changed(change) }
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let poll: @Sendable (TimeInterval) async throws -> Void
    /// Hides the typing indicator after `typingTimeout` without news.
    package private(set) var typingHide: Task<Void, Never>?
    /// A new conversation's wait for its flow's first step (`flowWaitTime`).
    package private(set) var flowWait: Task<Void, Never>?
    /// Asks for new messages while the socket is down (`pollInterval`).
    private var polling: Task<Void, Never>?
    /// A flow's wait for a choice that is not on screen (`ChatSnapshot.waitsForNothingShown`): after `flowWaitTime`
    /// the composer is back.
    package private(set) var stallWait: Task<Void, Never>?

    /// How often the messages are asked for while the socket is not connected.
    package static let pollInterval: TimeInterval = 5
    /// How long a new conversation waits for its flow's first step before it shows empty, and a flow that waits for a
    /// choice no longer on screen keeps the composer away.
    package static let flowWaitTime: TimeInterval = 8

    /// `known`: the user's name, email and phone, filled into forms. `config`: the one the messenger already has, so
    /// the first frame speaks the language the rest will (CM-087). The typing indicator hides itself after
    /// `typingTimeout` (6 s) without a new "typing" from the same sender, measured by `sleep`, as is the wait for a
    /// new conversation's flow; `poll` measures the checks for messages while the socket is down.
    package init(source: ChatDataSource, conversationId: String, language: String?, known: [String: String] = [:],
                config: MessengerConfig? = nil,
                timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() },
                typingTimeout: TimeInterval = 6,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                },
                poll: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }) {
        self.sleep = sleep
        self.poll = poll
        self.source = source
        self.conversationId = conversationId
        self.language = language
        self.timeZone = timeZone
        self.now = now
        self.typingTimeout = typingTimeout
        openedAt = now()
        snapshot = ChatSnapshot(config: config)
        snapshot.known = known
        // The language every other frame speaks: the host's, else the phone's, as the panel allows (not az by default).
        screen = ChatPresenter(strings: ClomniStrings(language: config.speaks(language), overrides: config?.strings ?? [:]),
                               timeZone: timeZone, now: now()).screen(snapshot)
    }

    private var strings: ClomniStrings {
        ClomniStrings(language: snapshot.config.speaks(language), overrides: snapshot.config?.strings ?? [:])
    }

    /// The cache at once, then the server; marks the conversation read. Until the messages and their buttons are
    /// known there is no composer (DESIGN-PASS-3 C5), so a flow's step never finds one to take away.
    package func load() async {
        startPolling()
        await read()
        render()
        if observation == nil {
            observation = await source.observe { [changes] change in changes.submit(change) }
        }
        if await source.conversation(conversationId) == nil {
            try? await source.refreshConversation(conversationId)
        }
        do {
            try await source.loadMessages(in: conversationId)
            snapshot.load = awaitsFlow(conversationId) ? .loading : .loaded
            if snapshot.load == .loading { waitForFlow() }
        } catch {
            snapshot.load = .failed
        }
        await read()
        render()
        await source.markRead(in: conversationId)
    }

    /// A new conversation whose inbox starts with a flow is created at once and its first step comes with it: until
    /// then nothing is known about the composer, so the screen waits. Offline, the user may write and queue instead.
    private func awaitsFlow(_ id: String) -> Bool {
        ClomniEngine.isDraft(id) && snapshot.config?.startsWithFlow == true && !isOffline
    }

    /// After `flowWaitTime` without the flow's first step, the empty conversation shows, its composer open.
    private func waitForFlow() {
        flowWait?.cancel()
        let wait = Self.flowWaitTime
        flowWait = Task { [weak self, sleep] in
            do {
                try await sleep(wait)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.snapshot.load == .loading else { return }
            self.snapshot.load = .loaded
            self.render()
        }
    }

    /// While the screen is open, every `pollInterval` the messages after the last known `seq` are asked for, unless
    /// the socket is connected and brings them itself: a socket that cannot connect (a wrong `ws_url`, a proxy) then
    /// costs liveliness, not messages.
    private func startPolling() {
        guard polling == nil else { return }
        let interval = Self.pollInterval
        polling = Task { [weak self, poll] in
            while !Task.isCancelled {
                do {
                    try await poll(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                if !(await self.source.isLive) {
                    try? await self.source.loadMessages(in: self.conversationId)
                }
            }
        }
    }

    /// "Yenidən cəhd et" after a failed first load.
    package func retry() async {
        snapshot.load = .loading
        render()
        await load()
    }

    /// When the screen goes away.
    package func stop() async {
        typingHide?.cancel()
        flowWait?.cancel()
        stallWait?.cancel()
        polling?.cancel()
        polling = nil
        if let observation {
            self.observation = nil
            await source.stopObserving(observation)
        }
        await source.setTyping(false, in: conversationId)
    }

    /// One page further back; false at the beginning.
    package func loadOlder() async -> Bool {
        let more = (try? await source.loadOlder(in: conversationId)) ?? false
        await read()
        render()
        return more
    }

    // MARK: - The user's actions

    /// false when the text cannot go (blank or over the limit); the composer keeps it then.
    @discardableResult
    package func send(_ text: String) async -> Bool {
        guard ChatPresenter.canSend(text, limit: screen.composer.limit) else { return false }
        let quoted = takeQuote()
        guard (try? await source.sendText(text, in: conversationId, replyTo: quoted)) != nil else { return false }
        sound(.sent)
        await source.setTyping(false, in: conversationId)
        return true
    }

    /// Swipe or "Cavabla": `messageId` is quoted over the field and goes with the next message, text or file; nil (the
    /// ✕) drops it.
    package func reply(to messageId: String?) {
        guard snapshot.replyingTo != messageId else { return }
        snapshot.replyingTo = messageId
        render()
    }

    /// The quote the composer shows, which the message being sent takes with it.
    private func takeQuote() -> String? {
        guard let quoted = screen.composer.quote?.messageId else { return nil }
        reply(to: nil)
        return quoted
    }

    /// The composer's text changed: typing is on while there is some.
    package func textChanged(_ text: String) async {
        await source.setTyping(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, in: conversationId)
    }

    /// A flow button, or "back" for "← Geri". A second tap finds the buttons gone and does nothing.
    package func tap(_ buttonId: String, in messageId: String) async {
        guard let message = snapshot.messages.first(where: { $0.id == messageId }),
              case .quickReplies(let replies) = message.content else { return }
        sound(.sent)
        if buttonId == "back" {
            _ = try? await source.goBack(from: message)
        } else if let button = replies.buttons.first(where: { $0.id == buttonId }) {
            _ = try? await source.reply(to: message, with: button)
        }
        await read()
        render()
    }

    /// Sends a form; returns the errors to show by field, empty when it went.
    package func submit(_ messageId: String, values: [String: String]) async -> [String: String] {
        guard let message = snapshot.messages.first(where: { $0.id == messageId }),
              case .form(let form) = message.content else { return [:] }
        let errors = FormInput.errors(form, values: values, strings: strings)
        guard errors.isEmpty else { return errors }
        sound(.sent)
        _ = try? await source.submitForm(message, values: FormInput.payload(form, values: values))
        await read()
        render()
        return [:]
    }

    /// A rating's score, with the comment when the card has a field. It goes through the outbox like any message
    /// (offline it waits there); should it fail, the card is open again.
    package func rate(_ messageId: String, score: Int, comment: String?) async {
        guard let message = snapshot.messages.first(where: { $0.id == messageId }),
              case .rating(let rating) = message.content else { return }
        let text = comment.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ChatPresenter.commentLimit)) }
            .flatMap { $0.isEmpty || rating.comment == .hidden ? nil : $0 }
        guard rating.comment != .required || text != nil,
              (try? await source.submitRating(message, score: score, comment: text)) != nil else { return }
        sound(.sent)
        await read()
        render()
    }

    /// "Göndərilmədi · Yenidən cəhd et".
    package func retrySending(_ clientId: String) async {
        try? await source.retry(clientId)
    }

    /// An image (already scaled, see `Media.uploadSize`) or a file; returns the text to show when it is refused.
    package func sendFile(_ data: Data, fileName: String, mime: String, caption: String? = nil) async -> String? {
        let quoted = takeQuote()
        do {
            _ = try await source.sendFile(data, fileName: fileName, mime: mime, caption: caption, in: conversationId,
                                          replyTo: quoted, voice: nil)
            sound(.sent)
            return nil
        } catch ClomniError.rejected {
            let limits = snapshot.config?.limits
            return strings.format(.fileTooLarge, Media.isImage(mime: mime) ? limits?.imageMb ?? 10 : limits?.fileMb ?? 25)
        } catch {
            return strings[.error]
        }
    }

    /// A recorded voice message (CM-130): sent like a file, through the outbox (kept on the device, uploaded, then sent
    /// with its length and waveform), so it waits with its clock while offline. The recording goes once the outbox has
    /// its own copy. Returns the text to show when it could not go.
    package func sendVoice(_ clip: VoiceClip) async -> String? {
        let quoted = takeQuote()
        defer { try? FileManager.default.removeItem(at: clip.file) }
        do {
            let data = try Data(contentsOf: clip.file)
            _ = try await source.sendFile(data, fileName: clip.file.lastPathComponent, mime: Self.voiceMime, caption: nil,
                                          in: conversationId, replyTo: quoted,
                                          voice: ClientMessage.Voice(durationMs: clip.durationMs, waveform: clip.waveform))
            sound(.sent)
            return nil
        } catch {
            return strings[.error]
        }
    }

    /// A recording's type: AAC in MP4 (.m4a), what the server plays and the panel's player opens.
    package static let voiceMime = "audio/mp4"

    /// "Yeni söhbət başlat": this screen moves to a new conversation's draft, which the server creates with its
    /// first message.
    package func startNewConversation() async {
        typingHide?.cancel()
        flowWait?.cancel()
        await source.setTyping(false, in: conversationId)
        conversationId = await source.draftConversation(openedFrom: nil)
        let known = snapshot.known
        snapshot = ChatSnapshot()
        snapshot.known = known
        await load()
    }

    // MARK: - The engine's changes

    /// Every change the engine reported so far is on screen.
    package func settled() async {
        await changes.settled()
    }

    func changed(_ change: ClomniChange) async {
        switch change {
        case .messages(let id) where id == conversationId:
            let known = Set(snapshot.messages.map(\.id))
            await read()
            // Something new from the other side while the conversation is on screen.
            if snapshot.messages.contains(where: {
                !known.contains($0.id) && $0.createdAt >= openedAt && $0.sender.type != .user && $0.type != "system"
            }) {
                sound(.incoming)
            }
            // A message from whoever was typing ends the indicator at once (operator, 2026-10-05).
            if let typing = snapshot.typing,
               snapshot.messages.contains(where: { !known.contains($0.id) && $0.sender.isTyping(typing) }) {
                hideTyping()
            }
            render()
            await source.markRead(in: conversationId)
        // The user's own typing, echoed back, is not someone else writing; "off" ends it whoever it names
        // (operator, 2026-10-06).
        case .typing(let id, let sender, let isTyping) where id == conversationId && sender.type != .user:
            showTyping(isTyping ? sender : nil)
        // A copy of a message already here changes no message, but the one typing it has stopped. It comes after the
        // message's own `.messages`, so a new message takes the indicator away in the same redraw.
        case .arrived(let id, let sender) where id == conversationId:
            if let typing = snapshot.typing, sender.isTyping(typing) { showTyping(nil) }
        case .read(let id, _) where id == conversationId:
            await read()
            render()
        case .conversationCreated(let draft, let id) where draft == conversationId:
            conversationId = id
            await read()
            render()
        case .conversations, .config, .session:
            await read()
            render()
        default:
            return
        }
    }

    private func showTyping(_ sender: Sender?) {
        typingHide?.cancel()
        typingHide = nil
        snapshot.typing = sender
        render()
        // A flow waiting for a choice may have taken it away already.
        guard snapshot.typing != nil else { return }
        let timeout = typingTimeout
        typingHide = Task { [weak self, sleep] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.showTyping(nil)
        }
    }

    private func read() async {
        snapshot.config = await source.config
        snapshot.conversation = await source.conversation(conversationId)
        snapshot.messages = await source.messages(in: conversationId)
        snapshot.pending = await source.pending(in: conversationId)
        snapshot.readUpTo = await source.readByOperator(in: conversationId)
        var answerable: Set<String> = []
        for message in snapshot.messages where message.flow?.interactive == true || message.type == "rating" {
            if await source.canAnswer(message) { answerable.insert(message.id) }
        }
        snapshot.answerable = answerable
        var files: [String: URL] = [:]
        for pending in snapshot.pending where pending.upload != nil {
            files[pending.id] = await source.localFile(of: pending)
        }
        snapshot.localFiles = files
    }

    private func sound(_ sound: ChatSound) {
        if snapshot.config?.sounds != false { playSound?(sound) }
    }

    /// The indicator goes, and its timer with it.
    private func hideTyping() {
        typingHide?.cancel()
        typingHide = nil
        snapshot.typing = nil
    }

    private func render() {
        snapshot.isOffline = isOffline
        // A flow waiting for a choice: nobody is writing, and a later step must not bring back an old "typing".
        if snapshot.typing != nil, snapshot.awaitsChoice { hideTyping() }
        watchForADeadEnd()
        screen = ChatPresenter(strings: strings, timeZone: timeZone, now: now()).screen(snapshot)
        onChange?()
    }

    /// A flow that says it waits for a choice, with none on screen, gets `flowWaitTime` for its next step; then the
    /// composer is back (CM-087: a choice whose "next" is null left the user with neither choices nor a field). A step
    /// that comes, or the flow's state changing, ends it.
    private func watchForADeadEnd() {
        guard snapshot.waitsForNothingShown else {
            stallWait?.cancel()
            stallWait = nil
            snapshot.flowStalled = false
            return
        }
        guard stallWait == nil, !snapshot.flowStalled else { return }
        let wait = Self.flowWaitTime
        stallWait = Task { [weak self, sleep] in
            do {
                try await sleep(wait)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.stallWait = nil
            guard self.snapshot.waitsForNothingShown else { return }
            ClomniLog.info("the flow waits for a choice that is not there; the composer is back")
            self.snapshot.flowStalled = true
            self.render()
        }
    }
}
