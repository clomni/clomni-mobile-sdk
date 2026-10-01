import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// What the conversation screen reads and does; `ClomniEngine` is one, tests use a fake.
public protocol ChatDataSource: Sendable {
    var config: MessengerConfig? { get async }
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
    func sendText(_ text: String, in conversationId: String) async throws -> PendingMessage
    func reply(to message: Message, with button: MessageContent.Button) async throws -> PendingMessage
    func goBack(from message: Message) async throws -> PendingMessage
    func submitForm(_ message: Message, values: [String: JSONValue]) async throws -> PendingMessage
    func sendFile(_ data: Data, fileName: String, mime: String, caption: String?,
                  in conversationId: String) async throws -> PendingMessage
    func retry(_ clientId: String) async throws
    func startConversation(openedFrom: String?) async throws -> Conversation
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID
    func stopObserving(_ token: UUID) async
}

extension ClomniEngine: ChatDataSource {}

/// Keeps one conversation's screen current and turns taps into engine calls. The SwiftUI view observes it through
/// `onChange`.
@MainActor
public final class ChatController {
    public private(set) var screen: ChatScreen
    /// Called after `screen` changed.
    public var onChange: (() -> Void)?
    /// Changes when "Yeni söhbət başlat" opens a new conversation in place of a closed one.
    public private(set) var conversationId: String

    public var isOffline = false {
        didSet { render() }
    }

    private let source: ChatDataSource
    private let language: String?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let typingTimeout: TimeInterval
    private var snapshot: ChatSnapshot
    private var observation: UUID?
    private var typingHide: Task<Void, Never>?

    /// `known`: the user's name, email and phone, filled into forms. The typing indicator hides itself after
    /// `typingTimeout` (8 s) without news.
    public init(source: ChatDataSource, conversationId: String, language: String?, known: [String: String] = [:],
                timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() },
                typingTimeout: TimeInterval = 8) {
        self.source = source
        self.conversationId = conversationId
        self.language = language
        self.timeZone = timeZone
        self.now = now
        self.typingTimeout = typingTimeout
        snapshot = ChatSnapshot()
        snapshot.known = known
        screen = ChatPresenter(strings: ClomniStrings(language: language), timeZone: timeZone, now: now())
            .screen(snapshot)
    }

    private var strings: ClomniStrings {
        ClomniStrings(language: language ?? snapshot.config?.languages.first, overrides: snapshot.config?.strings ?? [:])
    }

    /// The cache at once, then the server; marks the conversation read.
    public func load() async {
        await read()
        render()
        if observation == nil {
            observation = await source.observe { [weak self] change in
                Task { @MainActor in await self?.changed(change) }
            }
        }
        if await source.conversation(conversationId) == nil {
            try? await source.refreshConversation(conversationId)
        }
        do {
            try await source.loadMessages(in: conversationId)
            snapshot.load = .loaded
        } catch {
            snapshot.load = .failed
        }
        await read()
        render()
        await source.markRead(in: conversationId)
    }

    /// "Yenidən cəhd et" after a failed first load.
    public func retry() async {
        snapshot.load = .loading
        render()
        await load()
    }

    /// When the screen goes away.
    public func stop() async {
        typingHide?.cancel()
        if let observation {
            self.observation = nil
            await source.stopObserving(observation)
        }
        await source.setTyping(false, in: conversationId)
    }

    /// One page further back; false at the beginning.
    public func loadOlder() async -> Bool {
        let more = (try? await source.loadOlder(in: conversationId)) ?? false
        await read()
        render()
        return more
    }

    // MARK: - The user's actions

    /// false when the text cannot go (blank or over the limit); the composer keeps it then.
    @discardableResult
    public func send(_ text: String) async -> Bool {
        guard ChatPresenter.canSend(text, limit: screen.composer.limit),
              (try? await source.sendText(text, in: conversationId)) != nil else { return false }
        await source.setTyping(false, in: conversationId)
        return true
    }

    /// The composer's text changed: typing is on while there is some.
    public func textChanged(_ text: String) async {
        await source.setTyping(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, in: conversationId)
    }

    /// A flow button, or "back" for "← Geri". A second tap finds the buttons gone and does nothing.
    public func tap(_ buttonId: String, in messageId: String) async {
        guard let message = snapshot.messages.first(where: { $0.id == messageId }),
              case .quickReplies(let replies) = message.content else { return }
        if buttonId == "back" {
            _ = try? await source.goBack(from: message)
        } else if let button = replies.buttons.first(where: { $0.id == buttonId }) {
            _ = try? await source.reply(to: message, with: button)
        }
        await read()
        render()
    }

    /// Sends a form; returns the errors to show by field, empty when it went.
    public func submit(_ messageId: String, values: [String: String]) async -> [String: String] {
        guard let message = snapshot.messages.first(where: { $0.id == messageId }),
              case .form(let form) = message.content else { return [:] }
        let errors = FormInput.errors(form, values: values, strings: strings)
        guard errors.isEmpty else { return errors }
        _ = try? await source.submitForm(message, values: FormInput.payload(form, values: values))
        await read()
        render()
        return [:]
    }

    /// "Göndərilmədi · Yenidən cəhd et".
    public func retrySending(_ clientId: String) async {
        try? await source.retry(clientId)
    }

    /// An image (already scaled, see `Media.uploadSize`) or a file; returns the text to show when it is refused.
    public func sendFile(_ data: Data, fileName: String, mime: String, caption: String? = nil) async -> String? {
        do {
            _ = try await source.sendFile(data, fileName: fileName, mime: mime, caption: caption, in: conversationId)
            return nil
        } catch ClomniError.rejected {
            let limits = snapshot.config?.limits
            return strings.format(.fileTooLarge, Media.isImage(mime: mime) ? limits?.imageMb ?? 10 : limits?.fileMb ?? 25)
        } catch {
            return strings[.error]
        }
    }

    /// "Yeni söhbət başlat": this screen moves to a new conversation; its id, or nil when it could not start.
    public func startNewConversation() async -> String? {
        guard let conversation = try? await source.startConversation(openedFrom: nil) else { return nil }
        typingHide?.cancel()
        await source.setTyping(false, in: conversationId)
        conversationId = conversation.id
        let known = snapshot.known
        snapshot = ChatSnapshot()
        snapshot.known = known
        await load()
        return conversation.id
    }

    // MARK: - The engine's changes

    func changed(_ change: ClomniChange) async {
        switch change {
        case .messages(let id) where id == conversationId:
            let before = snapshot.messages.last?.id
            await read()
            // A message from whoever was typing ends the indicator.
            if let typing = snapshot.typing, let last = snapshot.messages.last, last.id != before,
               last.sender.type == typing.type {
                snapshot.typing = nil
            }
            render()
            await source.markRead(in: conversationId)
        case .typing(let id, let sender, let isTyping) where id == conversationId:
            showTyping(isTyping ? sender : nil)
        case .read(let id, _) where id == conversationId:
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
        snapshot.typing = sender
        render()
        guard sender != nil else { return }
        let timeout = typingTimeout
        typingHide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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
        for message in snapshot.messages where message.flow?.interactive == true {
            if await source.canAnswer(message) { answerable.insert(message.id) }
        }
        snapshot.answerable = answerable
        var files: [String: URL] = [:]
        for pending in snapshot.pending where pending.upload != nil {
            files[pending.id] = await source.localFile(of: pending)
        }
        snapshot.localFiles = files
    }

    private func render() {
        snapshot.isOffline = isOffline
        screen = ChatPresenter(strings: strings, timeZone: timeZone, now: now()).screen(snapshot)
        onChange?()
    }
}
