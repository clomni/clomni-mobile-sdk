import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// What opening the messenger needs from the SDK below; `ClomniEngine` is one, tests use a fake.
package protocol MessengerSession: Sendable {
    var isLoggedIn: Bool { get async }
    var isAppDisabled: Bool { get async }
    var unreadTotal: Int { get async }
    var config: MessengerConfig? { get async }
    /// The cached config, synchronously: for the first frame.
    func cachedConfigFromDisk() -> MessengerConfig?
    func loginUnidentifiedUser() async throws
    func refreshConfig(language: String?) async -> MessengerConfig?
    func connect() async
    func draftConversation(openedFrom: String?) async -> String
    func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                   openedFrom: String?) async throws -> Conversation?
    func messages(in conversationId: String) async -> [Message]
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID
}

extension ClomniEngine: MessengerSession {}

/// A screen of the open messenger.
package enum MessengerRoute: Sendable, Equatable, Hashable {
    case home
    /// The conversations, from Home's "Mesajlar" card.
    case messages
    /// A conversation, or a new one's draft (`ClomniEngine.draftConversation`) until its first message.
    case conversation(String)
    /// A news item, from Home's news card.
    case news(String)
}

/// The optional floating button (brief 8 · 7.2): off unless the app or the panel turns it on.
package struct LauncherState: Sendable, Equatable {
    package static let size: Double = 56
    /// From the screen's side and bottom edges.
    package static let edgePadding: Double = 18
    /// The operator's line mascot in the circle (DESIGN-PASS-3 E1).
    package static let mascotSize: Double = 30
    /// Pressed, the button gives a little: this scale, in 120 ms.
    package static let pressedScale: Double = 0.94

    /// White lines when `on_primary` is light, black ones when it is dark.
    package static func whiteMascot(on onPrimary: RGBColor) -> Bool {
        onPrimary.luminance > 0.5
    }

    package let side: MessengerConfig.LauncherPosition
    /// Above the bottom edge, for a tab bar (`setBottomPadding`).
    package let bottomPadding: Double
    /// The unread count on the button: "3", "99+"; nil when nothing is unread.
    package let badge: String?
    package let accessibilityLabel: String
}

/// The app's callbacks (brief 8 · 9).
package struct MessengerEvents {
    /// With the `source` the app passed to `present`.
    package var messengerOpened: ((String?) -> Void)?
    package var messengerClosed: (() -> Void)?
    package var conversationStarted: ((String) -> Void)?
    package var unreadCountChanged: ((Int) -> Void)?
    /// A flow reached its END node, with the flow's id.
    package var flowCompleted: ((String) -> Void)?

    package init() {}
}

/// Opening and closing the messenger, the unread count, and the launcher's rule, without any UI: the UIKit layer
/// presents what `route` says and draws what `launcher` says, nothing else. With the launcher off and the messenger
/// closed, it asks for no view at all.
@MainActor
package final class MessengerCoordinator {
    package enum Readiness: Sendable, Equatable {
        case notReady
        case ready
        /// The App SDK inbox is switched off (403 app_disabled): nothing opens, no launcher.
        case disabled
    }

    package private(set) var readiness = Readiness.notReady
    /// The last `prepare` reached nothing (no network at a first launch, say): the open messenger shows "Nəsə səhv
    /// getdi" with "Yenidən cəhd et" instead of skeletons that would never end. Trying again clears it.
    package private(set) var preparationFailed = false
    /// The open messenger's screens, Home first, as a navigation stack shows them; empty while it is closed.
    package private(set) var stack: [MessengerRoute] = []
    /// The screen on top; nil while the messenger is closed.
    package var route: MessengerRoute? { stack.last }
    /// The `source` of the open messenger, written to a new conversation's `opened_from`.
    package private(set) var source: String?
    package private(set) var unreadTotal = 0
    package private(set) var config: MessengerConfig?
    package var events = MessengerEvents()
    /// Called after `route`, `readiness`, `unreadTotal` or the launcher changed.
    package var onChange: (() -> Void)?

    private let session: MessengerSession
    /// The host's language (`Clomni.setLanguage`), spoken when the panel has it on; `setLanguage` changes it.
    package private(set) var language: String?
    private var launcherOverride: Bool?
    private var bottomPaddingOverride: Double?
    private var listeners: [UUID: (Int) -> Void] = [:]
    private var observation: UUID?
    private lazy var changes = ChangeQueue { [weak self] change in await self?.changed(change) }
    /// END messages already seen, per conversation; a conversation's first look reports none (they are history).
    private var finished: [String: Set<String>] = [:]

    package init(session: MessengerSession, language: String? = nil) {
        self.session = session
        self.language = language
    }

    private var strings: ClomniStrings {
        ClomniStrings(language: config.speaks(language), overrides: config?.strings ?? [:])
    }

    /// Whether the UIKit layer should hold any Clomni view: only while the messenger is open or the launcher shows.
    package var wantsAnyView: Bool {
        route != nil || launcher != nil
    }

    /// Present only when turned on (`setLauncherVisible`, else the config's `launcher.visible`), the SDK is ready
    /// and the messenger is closed.
    package var launcher: LauncherState? {
        guard readiness == .ready, route == nil, launcherOverride ?? config?.theme.launcher.enabled ?? false else {
            return nil
        }
        let badge = unreadTotal > 0 ? (unreadTotal > 99 ? "99+" : String(unreadTotal)) : nil
        let label = strings[.sendCardTitle] + (unreadTotal > 0 ? ", \(strings[.unreadMessages])" : "")
        return LauncherState(side: config?.theme.launcher.position ?? .right,
                             bottomPadding: bottomPaddingOverride ?? Double(config?.theme.launcher.bottomPadding ?? 20),
                             badge: badge, accessibilityLabel: label)
    }

    // MARK: - Getting ready

    /// After initialize and login: listens to the SDK, takes the cached config and unread count, opens the socket.
    package func start() async {
        await listen()
        config = await session.config
        updateUnread(await session.unreadTotal)
        if await session.isAppDisabled {
            readiness = .disabled
        } else if await session.isLoggedIn {
            await openOnCache()
            await session.connect()
            config = await session.refreshConfig(language: config.speaks(language)) ?? config
            readiness = await session.isAppDisabled ? .disabled : .ready
        }
        changed()
    }

    /// A session (an anonymous visitor when the app has logged nobody in) and the config: what an open messenger
    /// needs. While this runs the screens show skeletons. false when the inbox is switched off or nothing could
    /// be reached.
    @discardableResult
    package func prepare() async -> Bool {
        guard readiness != .disabled else { return false }
        if preparationFailed {
            // Skeletons again while it tries.
            preparationFailed = false
            changed()
        }
        await listen()
        if await session.isLoggedIn { await openOnCache() }
        if !(await session.isLoggedIn) {
            do {
                try await session.loginUnidentifiedUser()
            } catch {
                return refuse(await session.isAppDisabled, "messenger cannot open: \(error)")
            }
        }
        if await session.isAppDisabled { return refuse(true, "") }
        await session.connect()
        config = await session.refreshConfig(language: config.speaks(language)) ?? config
        if await session.isAppDisabled { return refuse(true, "") }
        readiness = .ready
        updateUnread(await session.unreadTotal)
        changed()
        return true
    }

    /// Logged in with a kept look, the messenger is ready now, on the cache (DESIGN-PASS-3 C1, C2); the socket and the
    /// config's ETag check follow, and a changed config redraws the screens when it comes. Offline, or on a slow
    /// network, the user sees what they saw last time instead of skeletons.
    private func openOnCache() async {
        guard readiness == .notReady, !(await session.isAppDisabled),
              let cached = await session.config ?? session.cachedConfigFromDisk() else { return }
        config = config ?? cached
        readiness = .ready
        updateUnread(await session.unreadTotal)
        changed()
    }

    private func refuse(_ disabled: Bool, _ reason: String) -> Bool {
        if disabled {
            readiness = .disabled
            stack = []
            ClomniLog.error("this App SDK inbox is switched off in Clomni: the messenger does not open")
        } else {
            preparationFailed = true
            ClomniLog.error(reason)
        }
        changed()
        return false
    }

    /// `Clomni.setLanguage`: the texts in the language now spoken, the server's once it answers.
    package func setLanguage(_ language: String?) {
        guard language != self.language else { return }
        self.language = language
        changed()
        guard readiness == .ready else { return }
        Task { _ = await session.refreshConfig(language: config.speaks(language)) }
    }

    /// After `logout`: the messenger closes, the count goes to 0, and nothing shows until the next login.
    package func loggedOut() {
        dismiss()
        if readiness == .ready { readiness = .notReady }
        updateUnread(0)
        finished = [:]
        changed()
    }

    // MARK: - Opening and closing

    /// Home. false (and nothing opens) when the inbox is switched off.
    @discardableResult
    package func present(source: String? = nil) -> Bool {
        open(.home, source: source)
    }

    /// One conversation; from a push, `source` is "push".
    @discardableResult
    package func presentConversation(_ id: String, source: String? = nil) -> Bool {
        open(.conversation(id), source: source)
    }

    /// Shows a new conversation; the server creates it (and its flow starts) with the user's first message, so
    /// opening and closing asks the server for nothing. The draft's id, or nil when nothing opens.
    @discardableResult
    package func presentNewConversation(source: String? = nil) async -> String? {
        guard readiness != .disabled else { return nil }
        let draft = await session.draftConversation(openedFrom: route == nil ? source : self.source)
        return open(.conversation(draft), source: source) ? draft : nil
    }

    /// `Clomni.startFlow`: the flow bound to an app event, in a new conversation, shown when `openMessenger`.
    @discardableResult
    package func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                          source: String? = nil) async -> String? {
        guard readiness != .disabled, await prepare() else { return nil }
        let started = try? await session.startFlow(event, data: data, openMessenger: openMessenger, openedFrom: source)
        guard let conversation = started ?? nil else { return nil }
        conversationStarted(conversation.id)
        if openMessenger { open(.conversation(conversation.id), source: source) }
        return conversation.id
    }

    /// A move inside the open messenger: a screen pushed on top (Messages, a conversation), or back to Home.
    package func navigate(to route: MessengerRoute) {
        guard !stack.isEmpty else { return }
        if route == .home {
            stack = [.home]
        } else if stack.last != route {
            stack.append(route)
        }
        changed()
    }

    /// The back button: the screen under this one. Home has none.
    package func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        changed()
    }

    /// The navigation stack went back by itself (the swipe from the edge): only `count` screens are left.
    package func poppedTo(count: Int) {
        guard count >= 1, count < stack.count else { return }
        stack.removeLast(stack.count - count)
        changed()
    }

    /// `Clomni.dismiss()`, or the user closing it; the app returns to where it was.
    package func dismiss() {
        guard route != nil else { return }
        stack = []
        source = nil
        events.messengerClosed?()
        changed()
    }

    /// A conversation the user started from Home.
    package func conversationStarted(_ id: String) {
        events.conversationStarted?(id)
    }

    @discardableResult
    private func open(_ route: MessengerRoute, source: String?) -> Bool {
        guard readiness != .disabled else {
            ClomniLog.warning("this App SDK inbox is switched off in Clomni: present() does nothing")
            return false
        }
        let wasClosed = self.route == nil
        // The first frame in the brand's colours: the cached config if the engine has not handed it over yet.
        if config == nil { config = session.cachedConfigFromDisk() }
        // Home under every screen, so back always has somewhere to go.
        stack = route == .home ? [.home] : [.home, route]
        if wasClosed {
            self.source = source
            events.messengerOpened?(source)
        }
        changed()
        return true
    }

    // MARK: - Push

    /// `Clomni.handlePush`, for a tap on a Clomni notification: its conversation opens (`opened_from` "push") and its
    /// unread count reaches the listeners. false when nothing opens.
    @discardableResult
    package func handlePush(_ push: PushPayload) -> Bool {
        pushArrived(push)
        return presentConversation(push.conversationId, source: "push")
    }

    /// A Clomni push reached the app: the count it carries is the server's when it was sent; the socket's next count
    /// replaces it.
    package func pushArrived(_ push: PushPayload) {
        guard let total = push.unreadTotal, total != unreadTotal else { return }
        updateUnread(total)
        changed()
    }

    /// `Clomni.shouldShowForeground`: not while the messenger is open, on any screen, since it updates itself
    /// (foreground suppression).
    package var showsForegroundPushes: Bool {
        route == nil
    }

    // MARK: - Launcher

    package func setLauncherVisible(_ visible: Bool) {
        launcherOverride = visible
        changed()
    }

    /// Lifts the launcher above a bottom bar.
    package func setBottomPadding(_ padding: Double) {
        bottomPaddingOverride = max(0, padding)
        changed()
    }

    // MARK: - Unread count

    /// Called at once with the current count, then with every change, until removed.
    @discardableResult
    package func addUnreadCountListener(_ listener: @escaping (Int) -> Void) -> UUID {
        let token = UUID()
        listeners[token] = listener
        listener(unreadTotal)
        return token
    }

    package func removeUnreadCountListener(_ token: UUID) {
        listeners[token] = nil
    }

    private func updateUnread(_ total: Int) {
        guard total != unreadTotal else { return }
        unreadTotal = total
        listeners.values.forEach { $0(total) }
        events.unreadCountChanged?(total)
    }

    // MARK: - The SDK's changes

    private func listen() async {
        guard observation == nil else { return }
        observation = await session.observe { [changes] change in changes.submit(change) }
    }

    /// Every change the SDK reported so far is handled.
    package func settled() async {
        await changes.settled()
    }

    func changed(_ change: ClomniChange) async {
        switch change {
        case .unread(let total):
            updateUnread(total)
            changed()
        case .config:
            config = await session.config
            changed()
        case .messages(let conversationId):
            reportFinishedFlows(in: conversationId, await session.messages(in: conversationId))
        case .conversationCreated(_, let conversationId):
            conversationStarted(conversationId)
        default:
            break
        }
    }

    /// A message from the END node means its flow is complete (the server's convention, fixture 50). The only
    /// place onFlowCompleted is decided: when the socket's `flow.completed` {conversation_id, flow_id} event lands
    /// (CM-024), it replaces this guess here (CM-086).
    private func reportFinishedFlows(in conversationId: String, _ messages: [Message]) {
        let ends = messages.filter { $0.flow?.nodeId == "END" }
        guard let seen = finished[conversationId] else {
            finished[conversationId] = Set(ends.map(\.id))
            return
        }
        for message in ends where !seen.contains(message.id) {
            if let flowId = message.flow?.flowId { events.flowCompleted?(flowId) }
        }
        finished[conversationId] = seen.union(ends.map(\.id))
    }

    private func changed() {
        onChange?()
    }
}
