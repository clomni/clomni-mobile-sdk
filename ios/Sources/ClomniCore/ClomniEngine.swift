import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// What changed, for the screens to redraw.
public enum ClomniChange: Sendable, Equatable {
    case session
    case config
    case conversations
    /// Messages or pending messages of one conversation.
    case messages(conversationId: String)
    case unread(total: Int)
    case typing(conversationId: String, sender: Sender, isTyping: Bool)
    case read(conversationId: String, upToSeq: Int)
}

/// The SDK below the screens: the session, the socket, the cache and the outbox (brief 8 · 9: Api, Realtime, Store).
///
/// Messages are sent through the outbox: each one is on disk until the server has it, and is repeated with the same
/// `client_id` until then, so a message written offline or lost with the connection arrives once. Three failed
/// attempts mark it failed; `retry` sends it again.
public actor ClomniEngine {
    static let attempts = 3
    static let cachedMessagesPerConversation = 100

    private let api: ApiClient
    private let realtime: RealtimeClient
    private let cache: DiskCache
    private let time: TimeSource
    private var store: MessageStore
    private var outbox: Outbox
    public private(set) var config: MessengerConfig?
    private var configETag: String?
    /// The inbox is switched off in Clomni: the messenger must not open.
    public private(set) var isAppDisabled = false
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]
    private var wantsSocket = false
    private var delivering: Task<Void, Never>?
    /// Tells a cancelled delivery loop apart from the one that replaced it.
    private var deliveryRun = 0
    /// NotificationCenter observers of the app's foreground and background (iOS).
    var lifecycleObservers: [Any] = []
    private var filling: Set<String> = []
    private var refill: Set<String> = []
    private var readSent: [String: Int] = [:]
    private var typingSentAt: [String: Date] = [:]

    public init(appId: String, apiKey: String, baseURL: URL? = nil) {
        #if canImport(Security)
        let vault: SecureStore = KeychainStore(appId: appId)
        #else
        let vault: SecureStore = MemorySecureStore()
        #endif
        self.init(configuration: ApiConfiguration(appId: appId, apiKey: apiKey, baseURL: baseURL ?? ApiConfiguration.defaultBaseURL),
                  transport: URLSessionTransport(), socket: URLSessionWebSocketTransport(), vault: vault,
                  cache: .standard(appId: appId), time: SystemTime())
    }

    init(configuration: ApiConfiguration, transport: HTTPTransport, socket: WebSocketTransport, vault: SecureStore,
         cache: DiskCache, time: TimeSource) {
        let api = ApiClient(configuration: configuration, transport: transport, vault: vault, time: time)
        self.api = api
        self.cache = cache
        self.time = time
        realtime = RealtimeClient(transport: socket, time: time, address: { try await api.socketURL() })
        store = cache.load(MessageStore.self, Files.store) ?? MessageStore()
        outbox = cache.load(Outbox.self, Files.outbox) ?? Outbox()
        config = cache.read(Files.config).flatMap(ProtocolJSON.parseConfig)
        configETag = cache.read(Files.configETag).map { String(decoding: $0, as: UTF8.self) }
    }

    private enum Files {
        static let store = "store.json"
        static let outbox = "outbox.json"
        static let config = "config.json"
        static let configETag = "config.etag"
    }

    /// `handler` hears every change until `stopObserving` is called with the returned token. Any number of screens
    /// can listen at once (Home, a conversation, the unread badge).
    @discardableResult
    public func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func stopObserving(_ token: UUID) {
        observers[token] = nil
    }

    // MARK: - Session

    public var isLoggedIn: Bool {
        get async { await api.session != nil }
    }

    /// An anonymous visitor; the same one again on this device until logout.
    public func loginUnidentifiedUser() async throws {
        try await login(.anonymous)
    }

    /// `userHash` = hex(HMAC-SHA256(identity_secret, user_id)), computed on the customer's server. An anonymous user's
    /// conversations move to this user.
    public func loginUser(_ user: UserIdentity, userHash: String?) async throws {
        try await login(.user(user, hash: userHash))
    }

    private func login(_ identity: SessionIdentity) async throws {
        let previous = await api.session
        let session: MobileSession
        do {
            session = try await api.open(identity)
        } catch {
            noteDisabled(error)
            throw error
        }
        isAppDisabled = false
        // Another identified user's conversations are not this one's.
        if let previous, !previous.anonymous, previous.userId != session.userId {
            clearLocalData()
        }
        notify(.session)
        if wantsSocket {
            await realtime.stop()
            await realtime.start()
        }
        deliver()
    }

    /// Ends the session and deletes everything kept on this device for the user.
    public func logout() async {
        wantsSocket = false
        await realtime.stop()
        delivering?.cancel()
        delivering = nil
        deliveryRun += 1
        await api.logout()
        clearLocalData()
        config = nil
        configETag = nil
        cache.clear()
        notify(.session)
    }

    private func clearLocalData() {
        store = MessageStore()
        outbox = Outbox()
        readSent = [:]
        save()
        notify(.conversations)
        notify(.unread(total: 0))
    }

    // MARK: - Socket

    /// Opens the socket (and keeps it open, reconnecting) while the app is in the foreground.
    public func connect() async {
        wantsSocket = true
        #if canImport(UIKit) && !os(watchOS)
        observeApplicationState()
        #endif
        await realtime.setHandler { [weak self] event in await self?.handle(event) }
        await realtime.start()
        deliver()
    }

    public func disconnect() async {
        wantsSocket = false
        await realtime.stop()
    }

    /// In the background the socket is closed and replies arrive as push notifications.
    public func applicationDidEnterBackground() async {
        await realtime.stop()
    }

    public func applicationWillEnterForeground() async {
        if wantsSocket { await realtime.start() }
        deliver()
    }

    func handle(_ event: RealtimeEvent) async {
        switch event.data {
        case .ready:
            Task { await self.catchUp() }
        case .messageCreated(let message), .messageUpdated(let message):
            receive(message, fromSocket: true)
        case .typing(let conversationId, let sender, let isTyping):
            notify(.typing(conversationId: conversationId, sender: sender, isTyping: isTyping))
        case .read(let conversationId, let upToSeq, let by):
            guard by == .operator else { return }
            store.markReadByOperator(conversationId, upToSeq: upToSeq)
            save()
            notify(.read(conversationId: conversationId, upToSeq: upToSeq))
        case .conversationUpdated(let update):
            store.apply(update)
            save()
            notify(.conversations)
        case .unreadChanged(let total):
            store.unreadTotal = total
            save()
            notify(.unread(total: total))
        case .configChanged:
            Task { await self.refreshConfig() }
        case .unknown:
            break
        }
    }

    /// After `ready`: the conversation list, what each open conversation missed, and the outbox.
    func catchUp() async {
        try? await refreshConversations()
        for (conversationId, messages) in store.messages {
            guard let newest = messages.last?.seq else { continue }
            if let latest = store.conversations[conversationId]?.lastMessage?.seq, latest <= newest,
               store.firstGap(in: conversationId) == nil {
                continue
            }
            try? await fetch(conversationId, after: newest)
            fillGaps(conversationId)
        }
        deliver()
    }

    // MARK: - Reading

    public var unreadTotal: Int { store.unreadTotal }

    public func conversations() -> [Conversation] {
        store.sortedConversations
    }

    public func messages(in conversationId: String) -> [Message] {
        store.messages(in: conversationId)
    }

    /// The user's messages not yet confirmed by the server, oldest first; shown after `messages(in:)`.
    public func pending(in conversationId: String) -> [PendingMessage] {
        outbox.entries(in: conversationId)
    }

    /// Whether a message's buttons (or form) are live.
    public func canAnswer(_ message: Message) -> Bool {
        store.canAnswer(message)
    }

    /// The highest seq the operator has read ("Oxundu").
    public func readByOperator(in conversationId: String) -> Int? {
        store.readUpTo[conversationId]
    }

    /// The config kept from last time, checked with its ETag.
    @discardableResult
    public func refreshConfig(language: String? = nil) async -> MessengerConfig? {
        do {
            if case .changed(let config, let body, let etag) = try await api.config(language: language, etag: configETag) {
                self.config = config
                configETag = etag
                cache.write(body, Files.config)
                cache.write(etag.map { Data($0.utf8) }, Files.configETag)
                notify(.config)
            }
        } catch {
            noteDisabled(error)
            CoreLog.write("config not refreshed: \(error)")
        }
        return config
    }

    public func refreshConversations() async throws {
        let page = try await api.conversations()
        page.conversations.forEach { store.upsert($0) }
        save()
        notify(.conversations)
    }

    /// Starts the inbox's new-conversation flow; its first messages come with it.
    public func startConversation(openedFrom: String?) async throws -> Conversation {
        let created = try await api.createConversation(openedFrom: openedFrom)
        apply(created)
        return created.conversation
    }

    /// Brings a conversation up to date: the latest page the first time, what is newer than the cache after that.
    public func loadMessages(in conversationId: String) async throws {
        if let newest = store.lastSeq(in: conversationId) {
            try await fetch(conversationId, after: newest)
        } else {
            let page = try await api.messages(in: conversationId)
            page.messages.forEach { receive($0) }
        }
    }

    /// One page further back; false when the beginning is reached.
    public func loadOlder(in conversationId: String) async throws -> Bool {
        guard let oldest = store.messages(in: conversationId).first?.seq else {
            try await loadMessages(in: conversationId)
            return true
        }
        guard oldest > 1 else { return false }
        let page = try await api.messages(in: conversationId, beforeSeq: oldest)
        page.messages.forEach { receive($0) }
        return page.hasMore
    }

    /// Up to the newest message; sent once per new seq.
    public func markRead(in conversationId: String) async {
        guard let newest = store.lastSeq(in: conversationId), newest > readSent[conversationId] ?? 0 else { return }
        readSent[conversationId] = newest
        store.markSeen(conversationId)
        save()
        notify(.conversations)
        do {
            try await api.markRead(conversationId, upToSeq: newest)
        } catch {
            readSent[conversationId] = nil
        }
    }

    /// `on` at most every 3 seconds while typing, `off` once when the user stops.
    public func setTyping(_ isTyping: Bool, in conversationId: String) async {
        if isTyping {
            if let last = typingSentAt[conversationId], time.now().timeIntervalSince(last) < 3 { return }
            typingSentAt[conversationId] = time.now()
        } else if typingSentAt.removeValue(forKey: conversationId) == nil {
            return
        }
        try? await api.setTyping(conversationId, on: isTyping)
    }

    // MARK: - Sending

    @discardableResult
    public func sendText(_ text: String, in conversationId: String) throws -> PendingMessage {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClomniError.rejected("empty text") }
        guard text.count <= config?.limits.textChars ?? 4000 else { throw ClomniError.rejected("text over the limit") }
        return enqueue(.text(text), in: conversationId, preview: text)
    }

    /// A flow button. The message's buttons go dead at once, so a second tap sends nothing.
    @discardableResult
    public func reply(to message: Message, with button: MessageContent.Button) throws -> PendingMessage {
        try answer(message)
        return enqueue(.buttonReply(replyTo: message.id, buttonId: button.id, payload: button.payload),
                       in: message.conversationId, preview: button.title)
    }

    /// "← Geri" under quick replies with `allowBack`.
    @discardableResult
    public func goBack(from message: Message) throws -> PendingMessage {
        guard case .quickReplies(let replies) = message.content, replies.allowBack else {
            throw ClomniError.rejected("no back button")
        }
        try answer(message)
        return enqueue(.back(replyTo: message.id), in: message.conversationId, preview: nil)
    }

    @discardableResult
    public func submitForm(_ message: Message, values: [String: JSONValue]) throws -> PendingMessage {
        guard case .form(let form) = message.content else { throw ClomniError.rejected("not a form") }
        try answer(message)
        return enqueue(.formSubmit(replyTo: message.id, formId: form.formId, values: values),
                       in: message.conversationId, preview: nil)
    }

    @discardableResult
    public func submitRating(_ message: Message, score: Int, comment: String?) throws -> PendingMessage {
        guard case .rating(let rating) = message.content, rating.submitted == nil, !store.answered.contains(message.id),
              (1...5).contains(score) else { throw ClomniError.rejected("rating not open") }
        store.markAnswered(message.id)
        return enqueue(.ratingSubmit(replyTo: message.id, score: score, comment: comment), in: message.conversationId,
                       preview: nil)
    }

    /// `uploadId` from `upload`.
    @discardableResult
    public func sendAttachment(uploadId: String, caption: String?, in conversationId: String) -> PendingMessage {
        enqueue(.attachment(uploadId: uploadId, caption: caption), in: conversationId, preview: caption)
    }

    public func upload(_ data: Data, fileName: String, mime: String) async throws -> UploadedFile {
        try await api.upload(data, fileName: fileName, mime: mime)
    }

    /// Sends a failed message again, with its original client id.
    public func retry(_ clientId: String) throws {
        guard outbox.entry(clientId)?.state == .failed else { throw ClomniError.rejected("nothing to retry") }
        outbox.update(clientId) {
            $0.state = .sending
            $0.attempts = 0
            $0.errorCode = nil
            $0.fields = [:]
        }
        changed(outbox.entry(clientId)?.conversationId)
        deliver()
    }

    public func discard(_ clientId: String) {
        changed(outbox.remove(clientId)?.conversationId)
    }

    private func answer(_ message: Message) throws {
        guard store.canAnswer(message) else { throw ClomniError.rejected("already answered") }
        store.markAnswered(message.id)
    }

    private func enqueue(_ content: ClientMessage.Content, in conversationId: String, preview: String?) -> PendingMessage {
        let entry = PendingMessage(conversationId: conversationId, message: ClientMessage(content: content), preview: preview,
                                   createdAt: time.now())
        outbox.add(entry)
        changed(conversationId)
        deliver()
        return entry
    }

    /// Works through the outbox in order, one message at a time.
    private func deliver() {
        guard delivering == nil else { return }
        deliveryRun += 1
        let run = deliveryRun
        delivering = Task {
            while !Task.isCancelled, await api.session != nil, let entry = outbox.next {
                await attempt(entry)
            }
            if run == deliveryRun { delivering = nil }
        }
    }

    private func attempt(_ entry: PendingMessage) async {
        do {
            let message = try await api.send(entry.message, to: entry.conversationId)
            outbox.remove(entry.id)
            receive(message)
            return
        } catch ClomniError.server(409, let error) {
            // already_answered / stale_interaction: the server has moved on; show its copy of the message.
            outbox.remove(entry.id)
            if let replyTo = entry.message.replyTo {
                store.markAnswered(replyTo)
                let seq = store.message(replyTo, in: entry.conversationId)?.seq
                Task { try? await self.fetch(entry.conversationId, after: max(0, (seq ?? 1) - 1)) }
            }
            CoreLog.write("\(entry.id): \(error?.code ?? "409"), dropped")
        } catch ClomniError.server(let status, let error) where (400..<500).contains(status) && status != 401 && status != 429 {
            outbox.update(entry.id) {
                $0.state = .failed
                $0.errorCode = error?.code
                $0.fields = error?.fields ?? [:]
            }
        } catch is CancellationError {
            return
        } catch {
            outbox.update(entry.id) { $0.attempts += 1 }
            let attempts = outbox.entry(entry.id)?.attempts ?? Self.attempts
            if attempts >= Self.attempts {
                outbox.update(entry.id) { $0.state = .failed }
            } else {
                changed(entry.conversationId)
                try? await time.sleep(seconds: pow(2, Double(attempts - 1)))
                return
            }
        }
        changed(entry.conversationId)
    }

    // MARK: - Incoming

    private func receive(_ message: Message, fromSocket: Bool = false) {
        let gap = store.insert(message, detectGap: fromSocket)
        // The server's copy of a pending message replaces the optimistic bubble.
        if let clientId = message.clientId { outbox.remove(clientId) }
        changed(message.conversationId)
        if gap != nil { fillGaps(message.conversationId) }
    }

    private func apply(_ created: ConversationWithMessages) {
        store.upsert(created.conversation)
        created.messages.forEach { receive($0) }
        save()
        notify(.conversations)
    }

    /// Every message after `seq`, page by page.
    private func fetch(_ conversationId: String, after seq: Int) async throws {
        var after = seq
        while true {
            let page = try await api.messages(in: conversationId, afterSeq: after, limit: 100)
            page.messages.forEach { receive($0) }
            guard page.hasMore, let newest = page.messages.last?.seq, newest > after else { return }
            after = newest
        }
    }

    /// Fetches the holes in a conversation's seq (40, 42 → 41), one fill per conversation at a time.
    private func fillGaps(_ conversationId: String) {
        guard !filling.contains(conversationId) else {
            refill.insert(conversationId)
            return
        }
        filling.insert(conversationId)
        Task {
            repeat {
                refill.remove(conversationId)
                while let start = store.firstGap(in: conversationId) {
                    let before = store.messages(in: conversationId).count
                    guard (try? await fetch(conversationId, after: start)) != nil,
                          store.messages(in: conversationId).count > before else { break }
                }
            } while refill.contains(conversationId)
            filling.remove(conversationId)
        }
    }

    // MARK: - User, push, flows

    /// Only the fields given change; `custom_attributes` are merged on the server.
    public func updateUser(_ fields: [String: JSONValue]) async throws -> MobileUser {
        try await api.updateUser(fields)
    }

    public func registerPushToken(_ token: String, sandbox: Bool) async throws {
        try await api.registerDevice(token: token, sandbox: sandbox)
    }

    public func unregisterPushToken(_ token: String) async throws {
        try await api.deleteDevice(token: token)
    }

    /// `Clomni.startFlow`: the flow bound to an app event, in a new conversation; nil when none is bound.
    public func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool) async throws -> Conversation? {
        let result = try await api.triggerFlow(event: event, data: data, openMessenger: openMessenger)
        guard let created = result.conversation else { return nil }
        apply(created)
        return created.conversation
    }

    public func track(_ event: String, data: [String: JSONValue]) async throws {
        try await api.track(event: event, data: data)
    }

    // MARK: -

    private func noteDisabled(_ error: Error) {
        if (error as? ClomniError)?.code == "app_disabled" { isAppDisabled = true }
    }

    private func changed(_ conversationId: String?) {
        save()
        if let conversationId { notify(.messages(conversationId: conversationId)) }
    }

    private func save() {
        cache.save(store.trimmed(to: Self.cachedMessagesPerConversation), Files.store)
        cache.save(outbox, Files.outbox)
    }

    private func notify(_ change: ClomniChange) {
        for observer in observers.values { observer(change) }
    }
}

extension ClientMessage {
    /// The message a button reply, form or rating answers.
    var replyTo: String? {
        switch content {
        case .buttonReply(let replyTo, _, _), .formSubmit(let replyTo, _, _), .ratingSubmit(let replyTo, _, _): return replyTo
        case .text, .attachment: return nil
        }
    }
}
