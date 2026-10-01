import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// What opening the messenger needs from the SDK below; `ClomniEngine` is one, tests use a fake.
public protocol MessengerSession: Sendable {
    var isLoggedIn: Bool { get async }
    var isAppDisabled: Bool { get async }
    var unreadTotal: Int { get async }
    var config: MessengerConfig? { get async }
    func loginUnidentifiedUser() async throws
    func refreshConfig(language: String?) async -> MessengerConfig?
    func connect() async
    func startConversation(openedFrom: String?) async throws -> Conversation
    func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                   openedFrom: String?) async throws -> Conversation?
    func messages(in conversationId: String) async -> [Message]
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID
}

extension ClomniEngine: MessengerSession {}

/// Where the open messenger is.
public enum MessengerRoute: Sendable, Equatable {
    case home
    /// A conversation being created: a skeleton until the server answers.
    case startingConversation
    case conversation(String)
}

/// The optional floating button (brief 8 · 7.2): off unless the app or the panel turns it on.
public struct LauncherState: Sendable, Equatable {
    public static let size: Double = 56
    /// From the screen's side and bottom edges.
    public static let edgePadding: Double = 18

    public let side: MessengerConfig.LauncherPosition
    /// Above the bottom edge, for a tab bar (`setBottomPadding`).
    public let bottomPadding: Double
    /// The unread count on the button: "3", "99+"; nil when nothing is unread.
    public let badge: String?
    public let accessibilityLabel: String
}

/// The app's callbacks (brief 8 · 9).
public struct MessengerEvents {
    /// With the `source` the app passed to `present`.
    public var messengerOpened: ((String?) -> Void)?
    public var messengerClosed: (() -> Void)?
    public var conversationStarted: ((String) -> Void)?
    public var unreadCountChanged: ((Int) -> Void)?
    /// A flow reached its END node, with the flow's id.
    public var flowCompleted: ((String) -> Void)?

    public init() {}
}

/// Opening and closing the messenger, the unread count, and the launcher's rule, without any UI: the UIKit layer
/// presents what `route` says and draws what `launcher` says, nothing else. With the launcher off and the messenger
/// closed, it asks for no view at all.
@MainActor
public final class MessengerCoordinator {
    public enum Readiness: Sendable, Equatable {
        case notReady
        case ready
        /// The App SDK inbox is switched off (403 app_disabled): nothing opens, no launcher.
        case disabled
    }

    public private(set) var readiness = Readiness.notReady
    /// nil while the messenger is closed.
    public private(set) var route: MessengerRoute?
    /// The `source` of the open messenger, written to a new conversation's `opened_from`.
    public private(set) var source: String?
    public private(set) var unreadTotal = 0
    public private(set) var config: MessengerConfig?
    public var events = MessengerEvents()
    /// Called after `route`, `readiness`, `unreadTotal` or the launcher changed.
    public var onChange: (() -> Void)?

    private let session: MessengerSession
    private let language: String?
    private var launcherOverride: Bool?
    private var bottomPaddingOverride: Double?
    private var listeners: [UUID: (Int) -> Void] = [:]
    private var observation: UUID?
    /// END messages already seen, per conversation; a conversation's first look reports none (they are history).
    private var finished: [String: Set<String>] = [:]

    public init(session: MessengerSession, language: String? = nil) {
        self.session = session
        self.language = language
    }

    private var strings: ClomniStrings {
        ClomniStrings(language: language ?? config?.languages.first, overrides: config?.strings ?? [:])
    }

    /// Whether the UIKit layer should hold any Clomni view: only while the messenger is open or the launcher shows.
    public var wantsAnyView: Bool {
        route != nil || launcher != nil
    }

    /// Present only when turned on (`setLauncherVisible`, else the config's `launcher.visible`), the SDK is ready
    /// and the messenger is closed.
    public var launcher: LauncherState? {
        guard readiness == .ready, route == nil, launcherOverride ?? config?.launcher.visible ?? false else {
            return nil
        }
        let badge = unreadTotal > 0 ? (unreadTotal > 99 ? "99+" : String(unreadTotal)) : nil
        let label = strings[.newConversation] + (unreadTotal > 0 ? ", \(strings[.unreadMessages])" : "")
        return LauncherState(side: config?.launcher.position ?? .right,
                             bottomPadding: bottomPaddingOverride ?? Double(config?.launcher.bottomPadding ?? 20),
                             badge: badge, accessibilityLabel: label)
    }

    // MARK: - Getting ready

    /// After initialize and login: listens to the SDK, takes the cached config and unread count, opens the socket.
    public func start() async {
        await listen()
        config = await session.config
        updateUnread(await session.unreadTotal)
        if await session.isAppDisabled {
            readiness = .disabled
        } else if await session.isLoggedIn {
            await session.connect()
            config = await session.refreshConfig(language: language) ?? config
            readiness = await session.isAppDisabled ? .disabled : .ready
        }
        changed()
    }

    /// A session (an anonymous visitor when the app has logged nobody in) and the config: what an open messenger
    /// needs. While this runs the screens show skeletons. false when the inbox is switched off or nothing could
    /// be reached.
    @discardableResult
    public func prepare() async -> Bool {
        guard readiness != .disabled else { return false }
        await listen()
        if !(await session.isLoggedIn) {
            do {
                try await session.loginUnidentifiedUser()
            } catch {
                return refuse(await session.isAppDisabled, "messenger cannot open: \(error)")
            }
        }
        if await session.isAppDisabled { return refuse(true, "") }
        await session.connect()
        config = await session.refreshConfig(language: language) ?? config
        if await session.isAppDisabled { return refuse(true, "") }
        readiness = .ready
        updateUnread(await session.unreadTotal)
        changed()
        return true
    }

    private func refuse(_ disabled: Bool, _ reason: String) -> Bool {
        if disabled {
            readiness = .disabled
            route = nil
            log("this App SDK inbox is switched off in Clomni: the messenger does not open")
        } else {
            log(reason)
        }
        changed()
        return false
    }

    /// After `logout`: the messenger closes, the count goes to 0, and nothing shows until the next login.
    public func loggedOut() {
        dismiss()
        if readiness == .ready { readiness = .notReady }
        updateUnread(0)
        finished = [:]
        changed()
    }

    // MARK: - Opening and closing

    /// Home. false (and nothing opens) when the inbox is switched off.
    @discardableResult
    public func present(source: String? = nil) -> Bool {
        open(.home, source: source)
    }

    /// One conversation; from a push, `source` is "push".
    @discardableResult
    public func presentConversation(_ id: String, source: String? = nil) -> Bool {
        open(.conversation(id), source: source)
    }

    /// Starts the inbox's new-conversation flow and shows it; its id, or nil when it could not start (Home stays).
    @discardableResult
    public func presentNewConversation(source: String? = nil) async -> String? {
        guard open(.startingConversation, source: source) else { return nil }
        guard await prepare(), let conversation = try? await session.startConversation(openedFrom: self.source) else {
            if route == .startingConversation { route = .home }
            changed()
            return nil
        }
        conversationStarted(conversation.id)
        if route != nil { route = .conversation(conversation.id) }
        changed()
        return conversation.id
    }

    /// `Clomni.startFlow`: the flow bound to an app event, in a new conversation, shown when `openMessenger`.
    @discardableResult
    public func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                          source: String? = nil) async -> String? {
        guard readiness != .disabled, await prepare() else { return nil }
        let started = try? await session.startFlow(event, data: data, openMessenger: openMessenger, openedFrom: source)
        guard let conversation = started ?? nil else { return nil }
        conversationStarted(conversation.id)
        if openMessenger { open(.conversation(conversation.id), source: source) }
        return conversation.id
    }

    /// A move inside the open messenger: Home, or a conversation picked there.
    public func navigate(to route: MessengerRoute) {
        guard self.route != nil else { return }
        self.route = route
        changed()
    }

    /// `Clomni.dismiss()`, or the user closing it; the app returns to where it was.
    public func dismiss() {
        guard route != nil else { return }
        route = nil
        source = nil
        events.messengerClosed?()
        changed()
    }

    /// A conversation the user started from Home.
    public func conversationStarted(_ id: String) {
        events.conversationStarted?(id)
    }

    @discardableResult
    private func open(_ route: MessengerRoute, source: String?) -> Bool {
        guard readiness != .disabled else {
            log("this App SDK inbox is switched off in Clomni: present() does nothing")
            return false
        }
        let wasClosed = self.route == nil
        self.route = route
        if wasClosed {
            self.source = source
            events.messengerOpened?(source)
        }
        changed()
        return true
    }

    // MARK: - Launcher

    public func setLauncherVisible(_ visible: Bool) {
        launcherOverride = visible
        changed()
    }

    /// Lifts the launcher above a bottom bar.
    public func setBottomPadding(_ padding: Double) {
        bottomPaddingOverride = max(0, padding)
        changed()
    }

    // MARK: - Unread count

    /// Called at once with the current count, then with every change, until removed.
    @discardableResult
    public func addUnreadCountListener(_ listener: @escaping (Int) -> Void) -> UUID {
        let token = UUID()
        listeners[token] = listener
        listener(unreadTotal)
        return token
    }

    public func removeUnreadCountListener(_ token: UUID) {
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
        observation = await session.observe { [weak self] change in
            Task { @MainActor in await self?.changed(change) }
        }
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

    private func log(_ line: String) {
        guard !line.isEmpty else { return }
        ProtocolJSON.logHandler?("[Clomni] \(line)")
    }
}
