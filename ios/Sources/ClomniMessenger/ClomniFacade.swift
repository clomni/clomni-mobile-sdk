#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import UserNotifications
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The opening API of brief 8 · 9 (names as on Android). Call it from the main thread. The facade's final shape
/// (what stays public, the thread model) is CM-086's.
@MainActor
extension Clomni {
    /// Prepares the connection and push; adds nothing to the app's screens. `region` "eu" is app.clomni.ai;
    /// `baseURL` overrides it.
    public static func initialize(appId: String, apiKey: String, region: String = "eu", baseURL: URL? = nil) {
        MessengerRuntime.shared.initialize(appId: appId, apiKey: apiKey, region: region, baseURL: baseURL)
    }

    /// `userHash` = hex(HMAC-SHA256(identity_secret, user_id)), from the app's server.
    public static func loginUser(_ user: ClomniUser, userHash: String?) {
        MessengerRuntime.shared.login { try await $0.loginUser(user.identity, userHash: userHash) }
    }

    public static func loginUnidentifiedUser() {
        MessengerRuntime.shared.login { try await $0.loginUnidentifiedUser() }
    }

    /// Ends the session and deletes the messenger's data on this device.
    public static func logout() {
        MessengerRuntime.shared.logout()
    }

    /// Home. `source` (where in the app, e.g. "profile_support") becomes a new conversation's `opened_from`.
    public static func present(source: String? = nil) {
        MessengerRuntime.shared.coordinator?.present(source: source)
    }

    /// Straight into a new conversation and its flow.
    public static func presentNewConversation(source: String? = nil) {
        guard let coordinator = MessengerRuntime.shared.coordinator else { return }
        Task { await coordinator.presentNewConversation(source: source) }
    }

    public static func presentConversation(_ id: String) {
        MessengerRuntime.shared.coordinator?.presentConversation(id)
    }

    public static func dismiss() {
        MessengerRuntime.shared.coordinator?.dismiss()
    }

    /// The flow bound to an app event (`payment_failed`, `ride_problem`), in a new conversation; opened on screen
    /// when `openMessenger`, otherwise announced by a push or the unread count.
    public static func startFlow(_ event: String, data: [String: Any] = [:], openMessenger: Bool = false,
                                 source: String? = nil) {
        guard let coordinator = MessengerRuntime.shared.coordinator else { return }
        guard let json = JSONValue(any: data)?.objectValue else {
            return MessengerRuntime.log("startFlow: data holds something JSON cannot carry")
        }
        Task { await coordinator.startFlow(event, data: json, openMessenger: openMessenger, source: source) }
    }

    /// The floating button, off by default; the panel can turn it on too.
    public static func setLauncherVisible(_ visible: Bool) {
        MessengerRuntime.shared.setLauncherVisible(visible)
    }

    /// Lifts the launcher above the app's tab bar.
    public static func setBottomPadding(_ padding: CGFloat) {
        MessengerRuntime.shared.setBottomPadding(Double(padding))
    }

    /// Called at once with the unread count, then on every change; for the app's own badge.
    @discardableResult
    public static func addUnreadCountListener(_ listener: @escaping (Int) -> Void) -> UUID {
        MessengerRuntime.shared.addUnreadCountListener(listener)
    }

    public static func removeUnreadCountListener(_ token: UUID) {
        MessengerRuntime.shared.removeUnreadCountListener(token)
    }

    /// From `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. Registered for whoever is logged in,
    /// and again for the next user. The APNs environment comes from the app's signature: a development profile means
    /// the sandbox; App Store and TestFlight builds are production.
    public static func setDeviceToken(_ token: Data) {
        MessengerRuntime.shared.setDeviceToken(PushToken.hex(token))
    }

    /// Whether a notification is Clomni's; the app's own pushes are none of the SDK's business.
    public nonisolated static func isClomniPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        ProtocolJSON.isClomniPush(userInfo)
    }

    /// From `userNotificationCenter(_:didReceive:withCompletionHandler:)` with
    /// `response.notification.request.content.userInfo`: opens the push's conversation. false for the app's own
    /// pushes.
    @discardableResult
    public static func handlePush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let coordinator = MessengerRuntime.shared.coordinator else {
            MessengerRuntime.log("handlePush: call Clomni.initialize first")
            return false
        }
        return coordinator.handlePush(userInfo)
    }

    /// From `userNotificationCenter(_:willPresent:withCompletionHandler:)`: false for a Clomni push while the
    /// messenger is open, true otherwise and for the app's own pushes.
    public static func shouldShowForeground(_ notification: UNNotification) -> Bool {
        shouldShowForeground(notification.request.content.userInfo)
    }

    public static func shouldShowForeground(_ userInfo: [AnyHashable: Any]) -> Bool {
        MessengerRuntime.shared.coordinator?.shouldShowForeground(userInfo) ?? true
    }

    public static var onMessengerOpened: ((String?) -> Void)? {
        get { MessengerRuntime.shared.events.messengerOpened }
        set { MessengerRuntime.shared.events.messengerOpened = newValue }
    }

    public static var onMessengerClosed: (() -> Void)? {
        get { MessengerRuntime.shared.events.messengerClosed }
        set { MessengerRuntime.shared.events.messengerClosed = newValue }
    }

    public static var onConversationStarted: ((String) -> Void)? {
        get { MessengerRuntime.shared.events.conversationStarted }
        set { MessengerRuntime.shared.events.conversationStarted = newValue }
    }

    public static var onUnreadCountChanged: ((Int) -> Void)? {
        get { MessengerRuntime.shared.events.unreadCountChanged }
        set { MessengerRuntime.shared.events.unreadCountChanged = newValue }
    }

    public static var onFlowCompleted: ((String) -> Void)? {
        get { MessengerRuntime.shared.events.flowCompleted }
        set { MessengerRuntime.shared.events.flowCompleted = newValue }
    }
}

/// Holds the engine and the coordinator, and does what the coordinator says in UIKit: presents the messenger full
/// screen from the top view controller, and shows the launcher in a window of its own, only as large as the button.
@MainActor
final class MessengerRuntime {
    static let shared = MessengerRuntime()

    private(set) var engine: ClomniEngine?
    private(set) var coordinator: MessengerCoordinator?
    /// Kept here so callbacks set before `initialize` are not lost.
    var events = MessengerEvents() {
        didSet { coordinator?.events = events }
    }

    private var launcherVisible: Bool?
    private var bottomPadding: Double?
    /// Listeners added before `initialize`, handed to the coordinator then.
    private var listeners: [(UUID, (Int) -> Void)] = []
    /// Their tokens, to the coordinator's.
    private var tokens: [UUID: UUID] = [:]
    /// An APNs token given before `initialize`, registered then.
    private var deviceToken: String?
    private var presented: UIViewController?
    private let rootModel = MessengerRootModel()
    private let launcher = LauncherController()

    static func baseURL(region: String) -> URL? {
        switch region.lowercased() {
        case "eu": return URL(string: "https://app.clomni.ai/v1")
        default:
            log("unknown region \"\(region)\", using eu")
            return URL(string: "https://app.clomni.ai/v1")
        }
    }

    static func log(_ line: String) {
        ProtocolJSON.logHandler?("[Clomni] \(line)")
    }

    func initialize(appId: String, apiKey: String, region: String, baseURL: URL?) {
        guard engine == nil else { return Self.log("initialize was called before; the first call stays") }
        let engine = ClomniEngine(appId: appId, apiKey: apiKey, baseURL: baseURL ?? Self.baseURL(region: region))
        let coordinator = MessengerCoordinator(session: engine)
        coordinator.events = events
        coordinator.onChange = { [weak self] in self?.render() }
        if let launcherVisible { coordinator.setLauncherVisible(launcherVisible) }
        if let bottomPadding { coordinator.setBottomPadding(bottomPadding) }
        for (token, listener) in listeners { tokens[token] = coordinator.addUnreadCountListener(listener) }
        listeners = []
        self.engine = engine
        self.coordinator = coordinator
        Task { await coordinator.start() }
        if let deviceToken { setDeviceToken(deviceToken) }
    }

    func setDeviceToken(_ token: String) {
        deviceToken = token
        guard let engine else { return }
        // The profile is read from disk: off the main thread.
        Task.detached(priority: .utility) {
            await engine.setDeviceToken(token, sandbox: PushToken.appIsSandbox)
        }
    }

    func login(_ action: @escaping (ClomniEngine) async throws -> Void) {
        guard let engine, let coordinator else { return Self.log("call Clomni.initialize first") }
        Task {
            do {
                try await action(engine)
            } catch {
                Self.log("login failed: \(error)")
            }
            await coordinator.start()
        }
    }

    func logout() {
        guard let engine, let coordinator else { return }
        coordinator.loggedOut()
        Task { await engine.logout() }
    }

    func setLauncherVisible(_ visible: Bool) {
        launcherVisible = visible
        coordinator?.setLauncherVisible(visible)
    }

    func setBottomPadding(_ padding: Double) {
        bottomPadding = padding
        coordinator?.setBottomPadding(padding)
    }

    func addUnreadCountListener(_ listener: @escaping (Int) -> Void) -> UUID {
        if let coordinator { return coordinator.addUnreadCountListener(listener) }
        let token = UUID()
        listeners.append((token, listener))
        listener(0)
        return token
    }

    func removeUnreadCountListener(_ token: UUID) {
        listeners.removeAll { $0.0 == token }
        coordinator?.removeUnreadCountListener(tokens.removeValue(forKey: token) ?? token)
    }

    /// Brings UIKit in line with the coordinator: nothing at all while closed and without a launcher.
    private func render() {
        guard let coordinator, let engine else { return }
        rootModel.update(from: coordinator)
        if coordinator.route != nil, presented == nil {
            present(MessengerRootView(model: rootModel, coordinator: coordinator, engine: engine))
        } else if coordinator.route == nil, let presented {
            self.presented = nil
            presented.dismiss(animated: true)
        }
        if let state = coordinator.launcher {
            launcher.show(state, config: coordinator.config) { [weak coordinator] in
                coordinator?.present(source: "launcher")
            }
        } else {
            launcher.hide()
        }
    }

    private func present(_ root: MessengerRootView) {
        guard let top = Self.topViewController() else { return Self.log("no window to present the messenger from") }
        let host = UIHostingController(rootView: root)
        // Full screen, sliding up; closing returns the app to where it was.
        host.modalPresentationStyle = .fullScreen
        presented = host
        top.present(host, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !($0 is LauncherWindow) }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The coordinator's state for SwiftUI.
@MainActor
final class MessengerRootModel: ObservableObject {
    @Published private(set) var route: MessengerRoute?
    @Published private(set) var ready = false
    @Published private(set) var config: MessengerConfig?
    @Published private(set) var source: String?

    func update(from coordinator: MessengerCoordinator) {
        if route != coordinator.route { route = coordinator.route }
        if ready != (coordinator.readiness == .ready) { ready = coordinator.readiness == .ready }
        if config != coordinator.config { config = coordinator.config }
        if source != coordinator.source { source = coordinator.source }
    }
}
#endif
