import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// What changed, for the screens to redraw.
package enum ClomniChange: Sendable, Equatable {
    case session
    case config
    case news
    case conversations
    /// Messages or pending messages of one conversation.
    case messages(conversationId: String)
    case unread(total: Int)
    case typing(conversationId: String, sender: Sender, isTyping: Bool)
    /// A message from `sender` came over the socket, new or a copy already held: they are no longer typing it.
    case arrived(conversationId: String, sender: Sender)
    case read(conversationId: String, upToSeq: Int)
    /// A new conversation's first message made the server create it: the draft's id is `conversationId` from now on.
    case conversationCreated(draft: String, conversationId: String)
}

/// The SDK below the screens: the session, the socket, the cache and the outbox (brief 8 · 9: Api, Realtime, Store).
///
/// Messages are sent through the outbox: each one is on disk until the server has it, and is repeated with the same
/// `client_id` until then, so a message written offline or lost with the connection arrives once. Without a connection
/// it keeps its clock and waits, however long, and goes as soon as the network is back (CM-087: the RN test on
/// Android). Only an answer counts against it: a refusal fails it at once, three server errors in a row fail it;
/// `retry` sends it again.
package actor ClomniEngine {
    static let attempts = 3
    static let cachedMessagesPerConversation = 100

    private let api: ApiClient
    private let realtime: RealtimeClient
    private let cache: DiskCache
    private let vault: SecureStore
    private let time: TimeSource
    // Read from disk on first use, on the actor and never on the caller's thread: `initialize` runs on the main thread
    // and must not wait for the disk.
    private lazy var store: MessageStore = cache.load(MessageStore.self, Files.store) ?? MessageStore()
    private lazy var outbox: Outbox = cache.load(Outbox.self, Files.outbox) ?? Outbox()
    package private(set) lazy var config: MessengerConfig? = cache.read(Files.config).flatMap(ProtocolJSON.parseConfig)
    /// The last news the server sent, from disk until it is asked.
    package private(set) lazy var news: [NewsItem] = cache.read(Files.news).flatMap(ProtocolJSON.parseNews) ?? []
    private lazy var configETag: String? = cache.read(Files.configETag).map { String(decoding: $0, as: UTF8.self) }
    /// The inbox is switched off in Clomni: the messenger must not open.
    package private(set) var isAppDisabled = false
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]
    private var wantsSocket = false
    private var delivering: Task<Void, Never>?
    /// Tells a cancelled delivery loop apart from the one that replaced it.
    private var deliveryRun = 0
    /// The delivery loop's wait for the network (`waitForNetwork`): the network coming back ends it at once.
    private var networkWait: UUID?
    /// Tries in a row that got no answer at all, for the wait before the next one.
    private var unanswered = 0
    /// The phone's network path (Network framework), followed while the socket is wanted.
    var networkObserver: AnyObject?
    /// NotificationCenter observers of the app's foreground and background (iOS).
    var lifecycleObservers: [Any] = []
    private var filling: Set<String> = []
    private var refill: Set<String> = []
    private var readSent: [String: Int] = [:]
    private var typingSentAt: [String: Date] = [:]
    private var pushRegistration: Task<Void, Never>?
    private var registerPushAgain = false
    private var configLanguage: String?
    /// New conversations not on the server yet, with their `opened_from`.
    private var drafts: [String: String?] = [:]
    /// Drafts the server has created, to their ids.
    private var createdDrafts: [String: String] = [:]
    /// Drafts whose POST /conversations is on its way (opened with a flow, or the first message): one request each.
    private var creating: [String: Task<Void, Error>] = [:]

    package init(appId: String, apiKey: String, baseURL: URL? = nil) {
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
        self.vault = vault
        self.time = time
        realtime = RealtimeClient(transport: socket, time: time, address: { try await api.socketURL() })
    }

    /// The config cached at the last launch, read from disk on the caller's thread (a few KB): for the messenger's
    /// first frame when this actor has not read it yet, so the brand's colours are there from the start.
    package nonisolated func cachedConfigFromDisk() -> MessengerConfig? {
        cache.read(Files.config).flatMap(ProtocolJSON.parseConfig)
    }

    private enum Files {
        static let store = "store.json"
        static let outbox = "outbox.json"
        static let config = "config.json"
        static let configETag = "config.etag"
        static let news = "news.json"
        static let newsETag = "news.etag"
        /// Kept in the vault, next to the session it was registered for (the system may purge the cache).
        static let push = "push_registration"
    }

    /// `handler` hears every change until `stopObserving` is called with the returned token. Any number of screens
    /// can listen at once (Home, a conversation, the unread badge).
    @discardableResult
    package func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    package func stopObserving(_ token: UUID) {
        observers[token] = nil
    }

    // MARK: - Session

    package var isLoggedIn: Bool {
        get async { await api.session != nil }
    }

    /// The logged-in user's name, for Home's greeting; nil for an anonymous visitor or a user without one.
    package var userName: String? {
        get async { await api.identity?.name }
    }

    /// An anonymous visitor; the same one again on this device until logout.
    package func loginUnidentifiedUser() async throws {
        try await login(.anonymous)
    }

    /// `userHash` = hex(HMAC-SHA256(identity_secret, user_id)), computed on the customer's server. An anonymous user's
    /// conversations move to this user.
    package func loginUser(_ user: UserIdentity, userHash: String?) async throws {
        // An empty name is none (a wrapper's "" for a missing one): the name kept with the identity stays, and the
        // server is not told to clear it.
        var user = user
        if user.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { user.name = nil }
        try await login(.user(user, hash: userHash))
    }

    private func login(_ identity: SessionIdentity) async throws {
        let previous = await api.session
        let previousName = await userName
        let session: MobileSession
        do {
            session = try await api.session(for: identity)
        } catch {
            noteDisabled(error)
            throw error
        }
        isAppDisabled = false
        Task { await self.registerPush() }
        guard session.sessionToken != previous?.sessionToken else {
            // The same session under a new name: Home greets them by it at once (G6).
            if await userName != previousName { notify(.session) }
            return deliverNow()
        }
        // Another identified user's conversations are not this one's.
        if let previous, !previous.anonymous, previous.userId != session.userId {
            clearLocalData()
        }
        notify(.session)
        if wantsSocket {
            await realtime.stop()
            await realtime.start()
        }
        deliverNow()
    }

    /// Ends the session and deletes everything kept on this device for the user.
    package func logout() async {
        wantsSocket = false
        await realtime.stop()
        delivering?.cancel()
        delivering = nil
        deliveryRun += 1
        networkWait = nil
        await api.logout()
        // The server dropped this device's token with the session; the next login registers it again.
        if var registration = vault.value(PushRegistration.self, for: Files.push) {
            registration.registeredFor = nil
            vault.setValue(registration, for: Files.push)
        }
        clearLocalData()
        config = nil
        news = []
        configETag = nil
        cache.clear()
        notify(.session)
    }

    private func clearLocalData() {
        store = MessageStore()
        outbox = Outbox()
        drafts = [:]
        createdDrafts = [:]
        readSent = [:]
        save()
        notify(.conversations)
        notify(.unread(total: 0))
    }

    // MARK: - Socket

    /// Opens the socket (and keeps it open, reconnecting) while the app is in the foreground.
    package func connect() async {
        wantsSocket = true
        #if canImport(UIKit) && !os(watchOS)
        observeApplicationState()
        #endif
        #if canImport(Network)
        observeNetwork()
        #endif
        await realtime.setHandler { [weak self] event in await self?.handle(event) }
        await realtime.start()
        deliverNow()
        Task { await self.registerPush() }
    }

    package func disconnect() async {
        wantsSocket = false
        await realtime.stop()
    }

    /// In the background the socket is closed and replies arrive as push notifications.
    package func applicationDidEnterBackground() async {
        await realtime.stop()
    }

    package func applicationWillEnterForeground() async {
        if wantsSocket { await realtime.start() }
        deliverNow()
        Task { await self.registerPush() }
    }

    func handle(_ event: RealtimeEvent) async {
        switch event.data {
        case .ready:
            Task { await self.catchUp() }
        case .messageCreated(let message):
            receive(message, fromSocket: true)
            if message.sender.type != .user { notify(.arrived(conversationId: message.conversationId, sender: message.sender)) }
        case .messageUpdated(let message):
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
        deliverNow()
    }

    // MARK: - Reading

    /// The socket is open and `ready` came: new messages arrive by themselves.
    package var isLive: Bool {
        get async { await realtime.state == .connected }
    }

    package var unreadTotal: Int { store.unreadTotal }

    package func conversations() -> [Conversation] {
        store.sortedConversations
    }

    package func messages(in conversationId: String) -> [Message] {
        store.messages(in: conversationId)
    }

    /// The user's messages not yet confirmed by the server, oldest first; shown after `messages(in:)`.
    package func pending(in conversationId: String) -> [PendingMessage] {
        outbox.entries(in: conversationId)
    }

    /// Whether a message's buttons (or form) are live.
    package func canAnswer(_ message: Message) -> Bool {
        store.canAnswer(message)
    }

    /// The highest seq the operator has read ("Oxundu").
    package func readByOperator(in conversationId: String) -> Int? {
        store.readUpTo[conversationId]
    }

    /// The config kept from last time, checked with its ETag.
    @discardableResult
    package func refreshConfig(language: String? = nil) async -> MessengerConfig? {
        // The config's texts are one language's; a refetch (config.changed) asks for the same one.
        let language = language ?? configLanguage
        configLanguage = language
        do {
            if case .changed(let config, let body, let etag) = try await api.config(language: language, etag: configETag) {
                ClomniLog.debug("config \(config.version) in \(language ?? "the server's language")")
                self.config = config
                configETag = etag
                cache.write(body, Files.config)
                cache.write(etag.map { Data($0.utf8) }, Files.configETag)
                notify(.config)
            }
        } catch {
            noteDisabled(error)
            ClomniLog.warning("config not refreshed: \(error)")
        }
        return config
    }

    /// The published news, in the language of the config's texts; the cached ones (from disk at first) when the
    /// server has nothing newer or cannot be reached.
    @discardableResult
    package func refreshNews() async -> [NewsItem] {
        do {
            let etag = cache.read(Files.newsETag).map { String(decoding: $0, as: UTF8.self) }
            if case .changed(let items, let body, let etag) = try await api.news(language: configLanguage, etag: etag) {
                news = items
                cache.write(body, Files.news)
                cache.write(etag.map { Data($0.utf8) }, Files.newsETag)
                notify(.news)
            }
        } catch {
            noteDisabled(error)
            ClomniLog.warning("news not refreshed: \(error)")
        }
        return news
    }

    /// Opening a news item, for the panel's analytics: the app event news_opened {news_id}.
    package func newsOpened(_ id: String) async {
        try? await track("news_opened", data: ["news_id": .string(id)])
    }

    package func refreshConversations() async throws {
        let page = try await api.conversations()
        page.conversations.forEach { store.upsert($0) }
        save()
        notify(.conversations)
    }

    /// A new conversation that exists only here until its first message: the server creates it then (starting the
    /// inbox's new-conversation flow), so opening and closing the messenger leaves nothing in the panel. When the inbox
    /// starts new conversations with a flow (`conversation.starts_with_flow`) it is created right away, with the
    /// draft's `client_id`, so the flow's first messages arrive without the user writing first.
    package func draftConversation(openedFrom: String?) -> String {
        let id = "\(Self.draftPrefix)\(UUID().uuidString.lowercased())"
        drafts[id] = openedFrom
        if config?.startsWithFlow == true {
            Task { try? await self.ensureCreated(id, openedFrom: openedFrom) }
        }
        return id
    }

    package static let draftPrefix = "draft_"

    package static func isDraft(_ conversationId: String) -> Bool {
        conversationId.hasPrefix(draftPrefix)
    }

    /// The server's id of a draft it has created; any other id as it is.
    package func resolved(_ conversationId: String) -> String {
        createdDrafts[conversationId] ?? conversationId
    }

    /// Brings a conversation up to date: the latest page the first time, what is newer than the cache after that.
    package func loadMessages(in conversationId: String) async throws {
        guard !Self.isDraft(conversationId) else { return }
        if let newest = store.lastSeq(in: conversationId) {
            try await fetch(conversationId, after: newest)
        } else {
            let page = try await api.messages(in: conversationId)
            page.messages.forEach { receive($0) }
        }
    }

    /// One page further back; false when the beginning is reached.
    package func loadOlder(in conversationId: String) async throws -> Bool {
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
    package func markRead(in conversationId: String) async {
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
    package func setTyping(_ isTyping: Bool, in conversationId: String) async {
        guard !Self.isDraft(conversationId) else { return }
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
    /// `replyTo`: the message the user answers, quoted over the new one.
    package func sendText(_ text: String, in conversationId: String, replyTo: String? = nil) throws -> PendingMessage {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClomniError.rejected("empty text") }
        guard text.count <= config?.limits.textChars ?? 4000 else { throw ClomniError.rejected("text over the limit") }
        return enqueue(.text(text), in: conversationId, preview: text, replyTo: replyTo)
    }

    /// A flow button. The message's buttons go dead at once, so a second tap sends nothing.
    @discardableResult
    package func reply(to message: Message, with button: MessageContent.Button) throws -> PendingMessage {
        try answer(message)
        return enqueue(.buttonReply(replyTo: message.id, buttonId: button.id, payload: button.payload),
                       in: message.conversationId, preview: button.title)
    }

    /// "← Geri" under quick replies with `allowBack`.
    @discardableResult
    package func goBack(from message: Message) throws -> PendingMessage {
        guard case .quickReplies(let replies) = message.content, replies.allowBack else {
            throw ClomniError.rejected("no back button")
        }
        try answer(message)
        return enqueue(.back(replyTo: message.id), in: message.conversationId, preview: nil)
    }

    @discardableResult
    package func submitForm(_ message: Message, values: [String: JSONValue]) throws -> PendingMessage {
        guard case .form(let form) = message.content else { throw ClomniError.rejected("not a form") }
        try answer(message)
        return enqueue(.formSubmit(replyTo: message.id, formId: form.formId, values: values),
                       in: message.conversationId, preview: nil)
    }

    @discardableResult
    package func submitRating(_ message: Message, score: Int, comment: String?) throws -> PendingMessage {
        // One that failed left the card open again: the new answer takes its place.
        let failed = outbox.entries(in: message.conversationId).filter {
            $0.state == .failed && $0.message.answeredId == message.id
        }
        guard case .rating(let rating) = message.content, rating.submitted == nil,
              !failed.isEmpty || !store.answered.contains(message.id), (1...5).contains(score) else {
            throw ClomniError.rejected("rating not open")
        }
        failed.forEach { removePending($0.id) }
        store.markAnswered(message.id)
        return enqueue(.ratingSubmit(replyTo: message.id, score: score, comment: comment), in: message.conversationId,
                       preview: nil)
    }

    /// `uploadId` from `upload`.
    @discardableResult
    package func sendAttachment(uploadId: String, caption: String?, in conversationId: String) -> PendingMessage {
        enqueue(.attachment(uploadId: uploadId, caption: caption), in: conversationId, preview: caption)
    }

    /// An image or file (images already scaled to at most 2048 px). It is kept on this device until the server has
    /// the message, so a lost connection or a restart does not lose it: the outbox uploads it, then sends it.
    @discardableResult
    package func sendFile(_ data: Data, fileName: String, mime: String, caption: String?,
                         in conversationId: String, replyTo: String? = nil) throws -> PendingMessage {
        let conversationId = resolved(conversationId)
        let megabytes = mime.hasPrefix("image/") ? config?.limits.imageMb ?? 10 : config?.limits.fileMb ?? 25
        guard data.count <= megabytes * 1_048_576 else { throw ClomniError.rejected("file over \(megabytes) MB") }
        let message = ClientMessage(content: .attachment(uploadId: "", caption: caption), replyTo: replyTo)
        let stored = "upload-\(message.clientId)"
        cache.write(data, stored)
        guard cache.contains(stored) else { throw ClomniError.rejected("file not stored") }
        var entry = PendingMessage(conversationId: conversationId, message: message, preview: caption,
                                   createdAt: time.now())
        entry.openedFrom = drafts[conversationId] ?? nil
        entry.upload = PendingUpload(fileName: fileName, mime: mime, size: data.count, storedAs: stored)
        outbox.add(entry)
        changed(conversationId)
        deliverNow()
        return entry
    }

    /// The file of a pending attachment, to show it before the server has it.
    package func localFile(of pending: PendingMessage) -> URL? {
        pending.upload.map { cache.directory.appendingPathComponent($0.storedAs) }
    }

    /// One conversation as the store knows it.
    package func conversation(_ id: String) -> Conversation? {
        store.conversations[id]
    }

    /// The conversation from the server, e.g. one opened from a push before the list knew it.
    package func refreshConversation(_ id: String) async throws {
        guard !Self.isDraft(id) else { return }
        store.upsert(try await api.conversation(id))
        save()
        notify(.conversations)
    }

    /// Whether a push's conversation is there to open: true when it is kept here or the server returns it, false
    /// on the server's 404 (`conversation_not_found`, as for the panel's test push "conv_test"), nil when the server
    /// could not be asked (offline, no session yet).
    package func conversationExists(_ id: String) async -> Bool? {
        if Self.isDraft(id) || store.conversations[id] != nil { return true }
        do {
            try await refreshConversation(id)
            return true
        } catch ClomniError.server(status: 404, _) {
            return false
        } catch {
            return nil
        }
    }

    package func upload(_ data: Data, fileName: String, mime: String) async throws -> UploadedFile {
        try await api.upload(data, fileName: fileName, mime: mime)
    }

    /// Sends a failed message again, with its original client id.
    package func retry(_ clientId: String) throws {
        guard outbox.entry(clientId)?.state == .failed else { throw ClomniError.rejected("nothing to retry") }
        outbox.update(clientId) {
            $0.state = .sending
            $0.attempts = 0
            $0.errorCode = nil
            $0.fields = [:]
        }
        changed(outbox.entry(clientId)?.conversationId)
        deliverNow()
    }

    package func discard(_ clientId: String) {
        changed(removePending(clientId)?.conversationId)
    }

    /// Takes a message out of the outbox, with its staged file.
    @discardableResult
    private func removePending(_ clientId: String) -> PendingMessage? {
        let entry = outbox.remove(clientId)
        if let upload = entry?.upload { cache.write(nil, upload.storedAs) }
        return entry
    }

    private func answer(_ message: Message) throws {
        guard store.canAnswer(message) else { throw ClomniError.rejected("already answered") }
        store.markAnswered(message.id)
    }

    private func enqueue(_ content: ClientMessage.Content, in conversationId: String, preview: String?,
                         replyTo: String? = nil) -> PendingMessage {
        let conversationId = resolved(conversationId)
        var entry = PendingMessage(conversationId: conversationId, message: ClientMessage(content: content, replyTo: replyTo),
                                   preview: preview, createdAt: time.now())
        entry.openedFrom = drafts[conversationId] ?? nil
        outbox.add(entry)
        ClomniLog.debug("queued \(entry.id) for \(conversationId)")
        changed(conversationId)
        deliverNow()
        return entry
    }

    /// The outbox goes now: a delivery loop that waits for the network tries again at once (the socket is back, the
    /// app came to the foreground, the user wrote or tapped retry); otherwise as `deliver`.
    private func deliverNow() {
        guard networkWait != nil, let waiting = delivering else { return deliver() }
        networkWait = nil
        waiting.cancel()
        delivering = nil
        unanswered = 0
        deliver()
    }

    /// The phone has a way to the network again (the system says so, or a screen saw it): what waits in the outbox
    /// goes at once rather than at the next try, and a socket waiting to reconnect tries now.
    package func networkAvailable() async {
        ClomniLog.debug("network is back")
        if wantsSocket { await realtime.reconnectNow() }
        deliverNow()
    }

    /// No answer: 1, 2, 4 … 30 s before the next try, unless the network comes back first (`deliverNow`).
    private func waitForNetwork() async {
        unanswered += 1
        let wait = UUID()
        networkWait = wait
        defer { if networkWait == wait { networkWait = nil } }
        try? await time.sleep(seconds: RealtimeClient.delay(afterFailures: unanswered - 1))
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
            var entry = entry
            if let upload = entry.upload, upload.uploadId == nil {
                guard let data = cache.read(upload.storedAs) else {
                    outbox.update(entry.id) {
                        $0.state = .failed
                        $0.errorCode = "file_missing"
                    }
                    return changed(entry.conversationId)
                }
                let uploaded = try await api.upload(data, fileName: upload.fileName, mime: upload.mime)
                outbox.update(entry.id) {
                    $0.upload?.uploadId = uploaded.uploadId
                    if case .attachment(_, let caption) = $0.message.content {
                        $0.message = ClientMessage(clientId: $0.message.clientId,
                                                   content: .attachment(uploadId: uploaded.uploadId, caption: caption),
                                                   replyTo: $0.message.replyTo)
                    }
                }
                save()
                guard let updated = outbox.entry(entry.id) else { return }
                entry = updated
            }
            if Self.isDraft(entry.conversationId) {
                try await ensureCreated(entry.conversationId, openedFrom: entry.openedFrom)
                guard let updated = outbox.entry(entry.id) else { return }
                entry = updated
            }
            let message = try await api.send(entry.message, to: entry.conversationId)
            unanswered = 0
            removePending(entry.id)
            receive(message)
            ClomniLog.debug("sent \(entry.id) as \(message.id)")
            return
        } catch ClomniError.server(409, let error) {
            // already_answered / stale_interaction: the server has moved on; show its copy of the message.
            removePending(entry.id)
            if let replyTo = entry.message.answeredId {
                store.markAnswered(replyTo)
                let seq = store.message(replyTo, in: entry.conversationId)?.seq
                Task { try? await self.fetch(entry.conversationId, after: max(0, (seq ?? 1) - 1)) }
            }
            ClomniLog.warning("\(entry.id): \(error?.code ?? "409"), dropped")
        } catch ClomniError.server(let status, let error) where (400..<500).contains(status) && status != 401 && status != 429 {
            outbox.update(entry.id) {
                $0.state = .failed
                $0.errorCode = error?.code
                $0.fields = error?.fields ?? [:]
            }
        } catch is CancellationError {
            return
        } catch ClomniError.network(let reason) {
            // No answer at all: the phone is offline, or the server cannot be reached. That is not the message's
            // fault: it keeps its clock and waits for the connection.
            ClomniLog.debug("send \(entry.id): no connection (\(reason)); it waits for the network")
            await waitForNetwork()
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

    /// The draft's first message is on its way: the server creates the conversation, once (the draft's messages
    /// move to its id at once and on disk), and the message follows with its own client id. The draft's UUID, on
    /// disk with its messages, is the start's `client_id`: a retry after a lost answer, or after a restart, gets the
    /// conversation the first request made.
    private func ensureCreated(_ draft: String, openedFrom: String?) async throws {
        guard createdDrafts[draft] == nil else { return }
        if let running = creating[draft] { return try await running.value }
        let task = Task { try await self.create(draft, openedFrom: openedFrom) }
        creating[draft] = task
        defer { creating[draft] = nil }
        try await task.value
    }

    private func create(_ draft: String, openedFrom: String?) async throws {
        let id = try await startConversation(openedFrom: openedFrom,
                                              clientId: String(draft.dropFirst(Self.draftPrefix.count))).id
        createdDrafts[draft] = id
        drafts[draft] = nil
        outbox.retarget(draft, to: id)
        save()
        notify(.conversationCreated(draft: draft, conversationId: id))
    }

    /// Creates a conversation on the server, which starts the inbox's new-conversation flow; its first messages come
    /// with it. Only through a draft's first message (and tests).
    func startConversation(openedFrom: String?, clientId: String? = nil) async throws -> Conversation {
        let created = try await api.createConversation(openedFrom: openedFrom, clientId: clientId)
        apply(created)
        return created.conversation
    }

    // MARK: - Incoming

    private func receive(_ message: Message, fromSocket: Bool = false) {
        let gap = store.insert(message, detectGap: fromSocket)
        // The server's copy of a pending message replaces the optimistic bubble.
        if let clientId = message.clientId { removePending(clientId) }
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
    package func updateUser(_ fields: [String: JSONValue]) async throws -> MobileUser {
        let before = await userName
        let user = try await api.updateUser(fields)
        if await userName != before { notify(.session) }
        return user
    }

    /// `Clomni.setDeviceToken`: the APNs token as hex, and whether the app is signed for the APNs sandbox. It is kept
    /// on this device and registered for whoever is logged in: now, at the next login, and again when another user
    /// logs in. A new token replaces the old one. A registration that fails is repeated at the next connect or return
    /// to the foreground.
    package func setDeviceToken(_ token: String, sandbox: Bool) async {
        let kept = vault.value(PushRegistration.self, for: Files.push)
        if kept?.token != token || kept?.sandbox != sandbox {
            vault.setValue(PushRegistration(token: token, sandbox: sandbox), for: Files.push)
        }
        await registerPush()
    }

    /// Sends the kept token unless the server already has it for the logged-in user. One run at a time: a call that
    /// arrives meanwhile makes the running one look again, and waits for it.
    func registerPush() async {
        if let running = pushRegistration {
            registerPushAgain = true
            return await running.value
        }
        let run = Task { await self.sendPushToken() }
        pushRegistration = run
        await run.value
    }

    private func sendPushToken() async {
        defer { pushRegistration = nil }
        repeat {
            registerPushAgain = false
            guard var registration = vault.value(PushRegistration.self, for: Files.push),
                  let user = await api.session?.userId, registration.registeredFor != user else { continue }
            // A failure waits for the next connect or foreground, unless a call came in meanwhile.
            guard (try? await api.registerDevice(token: registration.token, sandbox: registration.sandbox)) != nil else {
                continue
            }
            // The token, or the user, may have changed while the request was out.
            guard vault.value(PushRegistration.self, for: Files.push) == registration,
                  await api.session?.userId == user else {
                registerPushAgain = true
                continue
            }
            registration.registeredFor = user
            vault.setValue(registration, for: Files.push)
            ClomniLog.debug("push token registered (\(registration.sandbox ? "sandbox" : "production"))")
        } while registerPushAgain
    }

    /// `Clomni.startFlow`: the flow bound to an app event, in a new conversation; nil when none is bound.
    package func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                          openedFrom: String? = nil) async throws -> Conversation? {
        let result = try await api.triggerFlow(event: event, data: data, openMessenger: openMessenger,
                                               openedFrom: openedFrom)
        guard let created = result.conversation else { return nil }
        apply(created)
        return created.conversation
    }

    package func track(_ event: String, data: [String: JSONValue]) async throws {
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
    /// The message a button reply, form or rating answers (not `replyTo`, which is the quoted message of a text or an
    /// attachment).
    var answeredId: String? {
        switch content {
        case .buttonReply(let replyTo, _, _), .formSubmit(let replyTo, _, _), .ratingSubmit(let replyTo, _, _): return replyTo
        case .text, .attachment: return nil
        }
    }
}
