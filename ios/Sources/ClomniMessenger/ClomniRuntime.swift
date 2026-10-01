import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// What the facade needs from the SDK below; `ClomniEngine` is it, tests use a fake.
protocol ClomniBackend: MessengerSession {
    func loginUser(_ user: UserIdentity, userHash: String?) async throws
    func logout() async
    func updateUser(_ fields: [String: JSONValue]) async throws -> MobileUser
    func setDeviceToken(_ token: String, sandbox: Bool) async
}

extension ClomniEngine: ClomniBackend {}

/// Shows what the coordinator says on screen: UIKit on iOS (`UIKitMessenger`), nothing elsewhere.
@MainActor
protocol MessengerRenderer: AnyObject {
    func render()
    /// The app's font family, or nil for the system font.
    func setTypeface(_ family: String?)
}

/// The app's callbacks, run on the main thread.
struct ClomniEvents: Sendable {
    var messengerOpened: (@MainActor @Sendable (String?) -> Void)?
    var messengerClosed: (@MainActor @Sendable () -> Void)?
    var conversationStarted: (@MainActor @Sendable (String) -> Void)?
    var unreadCountChanged: (@MainActor @Sendable (Int) -> Void)?
    var flowCompleted: (@MainActor @Sendable (String) -> Void)?
}

/// What any thread may read without waiting for the main thread: the callbacks, and what `handlePush` and
/// `shouldShowForeground` answer at once. The runtime keeps it current on every change.
enum ClomniShared {
    struct State: Sendable {
        var events = ClomniEvents()
        var initialized = false
        var disabled = false
        var messengerOpen = false
    }

    static let state = Locked(State())
}

enum MainThread {
    /// Runs `work` on the main thread: at once when already there, else next on the main queue. Either way calls
    /// keep the order they were made in.
    static func run(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(work) }
        }
    }
}

/// Behind the `Clomni` facade, on the main thread: the engine and the coordinator, and what the app set before
/// `initialize` (launcher, padding, push token, unread listeners).
@MainActor
final class ClomniRuntime {
    static var shared = ClomniRuntime()

    typealias MakeBackend = @MainActor (_ appId: String, _ apiKey: String, _ baseURL: URL) -> ClomniBackend
    typealias MakeRenderer = @MainActor (ClomniBackend, MessengerCoordinator) -> MessengerRenderer?

    private let makeBackend: MakeBackend
    private let makeRenderer: MakeRenderer
    private let isSandbox: @Sendable () -> Bool
    private(set) var backend: ClomniBackend?
    private(set) var coordinator: MessengerCoordinator?
    private var renderer: MessengerRenderer?
    private var launcherVisible: Bool?
    private var bottomPadding: Double?
    private var deviceToken: String?
    private var typeface: String?
    private var listeners: [UUID: @MainActor @Sendable (Int) -> Void] = [:]
    private var unreadTotal = 0

    init(makeBackend: @escaping MakeBackend = ClomniRuntime.engine, makeRenderer: @escaping MakeRenderer = ClomniRuntime.screens,
         isSandbox: @escaping @Sendable () -> Bool = { PushToken.appIsSandbox }) {
        self.makeBackend = makeBackend
        self.makeRenderer = makeRenderer
        self.isSandbox = isSandbox
        ClomniShared.state.write { $0 = ClomniShared.State(events: $0.events) }
    }

    static func engine(appId: String, apiKey: String, baseURL: URL) -> ClomniBackend {
        ClomniEngine(appId: appId, apiKey: apiKey, baseURL: baseURL)
    }

    static func screens(_ backend: ClomniBackend, _ coordinator: MessengerCoordinator) -> MessengerRenderer? {
        #if canImport(SwiftUI) && canImport(UIKit)
        guard let engine = backend as? ClomniEngine else { return nil }
        return UIKitMessenger(engine: engine, coordinator: coordinator)
        #else
        return nil
        #endif
    }

    nonisolated static func baseURL(region: String) -> URL {
        let eu = URL(string: "https://app.clomni.ai/v1")!
        switch region.lowercased() {
        case "eu": return eu
        default:
            ClomniLog.error("unknown region \"\(region)\"; using eu")
            return eu
        }
    }

    /// The coordinator, or nil with a line saying `initialize` comes first.
    func coordinator(for call: String) -> MessengerCoordinator? {
        if coordinator == nil { ClomniLog.error("\(call): call Clomni.initialize first") }
        return coordinator
    }

    // MARK: - Setup

    func initialize(appId: String, apiKey: String, baseURL: URL) {
        guard backend == nil else { return ClomniLog.warning("initialize was called before; the first call stays") }
        let backend = makeBackend(appId, apiKey, baseURL)
        let coordinator = MessengerCoordinator(session: backend)
        coordinator.events = events()
        coordinator.addUnreadCountListener { [weak self] in self?.unreadChanged($0) }
        if let launcherVisible { coordinator.setLauncherVisible(launcherVisible) }
        if let bottomPadding { coordinator.setBottomPadding(bottomPadding) }
        self.backend = backend
        self.coordinator = coordinator
        renderer = makeRenderer(backend, coordinator)
        if let typeface { renderer?.setTypeface(typeface) }
        coordinator.onChange = { [weak self] in self?.changed() }
        ClomniShared.state.write { $0.initialized = true }
        if let deviceToken { setDeviceToken(deviceToken) }
        Task { await coordinator.start() }
    }

    /// The coordinator's events, passed on to whatever the app has set by the time they happen.
    private func events() -> MessengerEvents {
        var events = MessengerEvents()
        events.messengerOpened = { source in ClomniShared.state.read { $0.events.messengerOpened }?(source) }
        events.messengerClosed = { ClomniShared.state.read { $0.events.messengerClosed }?() }
        events.conversationStarted = { id in ClomniShared.state.read { $0.events.conversationStarted }?(id) }
        events.unreadCountChanged = { count in ClomniShared.state.read { $0.events.unreadCountChanged }?(count) }
        events.flowCompleted = { flow in ClomniShared.state.read { $0.events.flowCompleted }?(flow) }
        return events
    }

    private func changed() {
        guard let coordinator else { return }
        ClomniShared.state.write {
            $0.messengerOpen = coordinator.route != nil
            $0.disabled = coordinator.readiness == .disabled
        }
        renderer?.render()
    }

    func login(_ action: @escaping @Sendable (ClomniBackend) async throws -> Void) {
        guard let backend, let coordinator = coordinator(for: "login") else { return }
        Task {
            do {
                try await action(backend)
            } catch {
                ClomniLog.error("login failed: \(error)")
            }
            await coordinator.start()
        }
    }

    func updateUser(_ fields: [String: JSONValue]) {
        guard let backend, coordinator(for: "updateUser") != nil else { return }
        Task {
            do {
                _ = try await backend.updateUser(fields)
            } catch {
                ClomniLog.error("updateUser failed: \(error)")
            }
        }
    }

    func logout() {
        guard let backend, let coordinator else { return }
        coordinator.loggedOut()
        Task { await backend.logout() }
    }

    // MARK: - Launcher and push

    func setLauncherVisible(_ visible: Bool) {
        launcherVisible = visible
        coordinator?.setLauncherVisible(visible)
    }

    func setBottomPadding(_ padding: Double) {
        bottomPadding = padding
        coordinator?.setBottomPadding(padding)
    }

    func setTypeface(_ family: String?) {
        typeface = family
        renderer?.setTypeface(family)
    }

    func setDeviceToken(_ token: String) {
        deviceToken = token
        guard let backend else { return }
        let isSandbox = isSandbox
        // The provisioning profile is read from disk: off the main thread.
        Task.detached(priority: .utility) {
            await backend.setDeviceToken(token, sandbox: isSandbox())
        }
    }

    // MARK: - Unread count

    func addUnreadCountListener(_ token: UUID, _ listener: @escaping @MainActor @Sendable (Int) -> Void) {
        listeners[token] = listener
        listener(unreadTotal)
    }

    func removeUnreadCountListener(_ token: UUID) {
        listeners[token] = nil
    }

    private func unreadChanged(_ total: Int) {
        guard total != unreadTotal else { return }
        unreadTotal = total
        listeners.values.forEach { $0(total) }
    }
}
