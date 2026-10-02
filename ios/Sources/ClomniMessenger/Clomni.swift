import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The Clomni Messenger SDK. Everything the app calls is a static member of `Clomni` (brief 8 · 9).
///
/// Every method may be called from any thread; the work is done on the main thread, in the order of the calls.
/// Callbacks and events run on the main thread.
public enum Clomni {
    /// This SDK's version.
    public static let version: String = SDKInfo.version

    // MARK: - Setup

    /// Prepares the connection and push. Adds nothing to the app's screens: the messenger opens only when the app
    /// calls `present` (or turns the launcher on). Call it once, at launch. `region` is "eu".
    public static func initialize(appId: String, apiKey: String, region: String = "eu") {
        let baseURL = ClomniRuntime.baseURL(region: region)
        MainThread.run { ClomniRuntime.shared.initialize(appId: appId, apiKey: apiKey, baseURL: baseURL) }
    }

    /// The app's logged-in user. `userHash` is hex(HMAC-SHA256(identity_secret, userId)), computed on the app's
    /// server. Conversations of an anonymous visitor on this device move to the user.
    public static func loginUser(_ user: ClomniUser, userHash: String?) {
        let identity = user.identity
        MainThread.run { ClomniRuntime.shared.login { try await $0.loginUser(identity, userHash: userHash) } }
    }

    /// An anonymous visitor, the same one on this device until `logout`. Not needed before `present`: the messenger
    /// starts one itself when nobody is logged in.
    public static func loginUnidentifiedUser() {
        MainThread.run { ClomniRuntime.shared.login { try await $0.loginUnidentifiedUser() } }
    }

    /// Changes only what is given; `customAttributes` are merged with the user's existing ones. `language` is
    /// "az", "en" or "ru".
    public static func updateUser(name: String? = nil, language: String? = nil, customAttributes: [String: Any]? = nil) {
        var fields: [String: JSONValue] = [:]
        if let name { fields["name"] = .string(name) }
        if let language { fields["language"] = .string(language) }
        if let customAttributes {
            guard let json = JSONValue(any: customAttributes) else {
                return ClomniLog.error("updateUser: customAttributes hold something JSON cannot carry")
            }
            fields["custom_attributes"] = json
        }
        guard !fields.isEmpty else { return ClomniLog.warning("updateUser: nothing to change") }
        let changes = fields
        MainThread.run { ClomniRuntime.shared.updateUser(changes) }
    }

    /// Ends the session and deletes the messenger's data on this device. Call it when the app's user logs out, or
    /// the next user sees this one's conversations.
    public static func logout() {
        MainThread.run { ClomniRuntime.shared.logout() }
    }

    /// `none` writes nothing; the default is `warning`. Lines go to the system log as "[Clomni] error: …".
    public static func setLogLevel(_ level: ClomniLogLevel) {
        ClomniLog.level = level.level
    }

    // MARK: - Opening the messenger

    /// Home. `source` says where in the app (for example "profile_support") and is stored with a conversation
    /// started from here.
    public static func present(source: String? = nil) {
        MainThread.run { ClomniRuntime.shared.coordinator(for: "present")?.present(source: source) }
    }

    /// Straight into a new conversation, with the inbox's first flow.
    public static func presentNewConversation(source: String? = nil) {
        MainThread.run {
            guard let coordinator = ClomniRuntime.shared.coordinator(for: "presentNewConversation") else { return }
            Task { await coordinator.presentNewConversation(source: source) }
        }
    }

    /// One conversation, by its id (`onConversationStarted` gives it).
    public static func presentConversation(_ id: String) {
        MainThread.run { ClomniRuntime.shared.coordinator(for: "presentConversation")?.presentConversation(id) }
    }

    public static func dismiss() {
        MainThread.run { ClomniRuntime.shared.coordinator?.dismiss() }
    }

    /// Starts the flow bound to an app event (for example "payment_failed" or "ride_problem") in a new conversation.
    /// Its texts can use `data` as `{{data.order_id}}`. With `openMessenger` the conversation opens on screen;
    /// otherwise the user learns of it from a push or the unread count. Nothing happens when no flow is bound.
    public static func startFlow(_ event: String, data: [String: Any] = [:], openMessenger: Bool = false,
                                 source: String? = nil) {
        guard let json = JSONValue(any: data)?.objectValue else {
            return ClomniLog.error("startFlow: data holds something JSON cannot carry")
        }
        MainThread.run {
            guard let coordinator = ClomniRuntime.shared.coordinator(for: "startFlow") else { return }
            Task { await coordinator.startFlow(event, data: json, openMessenger: openMessenger, source: source) }
        }
    }

    /// The floating button: off by default, and the panel can turn it on too. The app's choice wins.
    public static func setLauncherVisible(_ visible: Bool) {
        MainThread.run { ClomniRuntime.shared.setLauncherVisible(visible) }
    }

    /// The app's own font family (for example "Montserrat") for every text of the messenger; it must be in the app
    /// (UIAppFonts). Text keeps following Dynamic Type. A weight the family lacks takes its nearest face. nil, or a
    /// family the app does not have, is the system font.
    public static func setTypeface(_ familyName: String?) {
        MainThread.run { ClomniRuntime.shared.setTypeface(familyName) }
    }

    /// The app's own look over the panel's (APPEARANCE-CONTRACT § 4). `primaryColor` "#RRGGBB": the other colours are
    /// derived from it by the panel's rules. `mode`: light, dark or as the system is. Each call replaces the last;
    /// nil leaves that value to the panel. `typeface` sets the font as `setTypeface` does; nil leaves it as it is.
    public static func setTheme(primaryColor: String? = nil, typeface: String? = nil, mode: ClomniThemeMode? = nil) {
        var color = primaryColor
        if let primaryColor, RGBColor(hex: primaryColor) == nil {
            ClomniLog.error("setTheme: primaryColor \"\(primaryColor)\" is not #RRGGBB; the panel's colour stays")
            color = nil
        }
        let override = ThemeOverride(primaryColor: color, mode: mode?.mode)
        MainThread.run {
            ClomniRuntime.shared.setThemeOverride(override)
            if let typeface { ClomniRuntime.shared.setTypeface(typeface) }
        }
    }

    /// Lifts the launcher above the app's tab bar, in points.
    public static func setBottomPadding(_ padding: Double) {
        MainThread.run { ClomniRuntime.shared.setBottomPadding(padding) }
    }

    // MARK: - Push

    /// From `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`. Registered for whoever is logged in,
    /// and again for the next user. A build signed with a development profile uses the APNs sandbox; App Store and
    /// TestFlight builds use production.
    public static func setDeviceToken(_ token: Data) {
        let hex = PushToken.hex(token)
        MainThread.run { ClomniRuntime.shared.setDeviceToken(hex) }
    }

    /// Whether a notification is Clomni's: `notification.request.content.userInfo`.
    public static func isClomniPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        ProtocolJSON.isClomniPush(userInfo)
    }

    /// For a tap on a notification (`userNotificationCenter(_:didReceive:withCompletionHandler:)`, with
    /// `response.notification.request.content.userInfo`): a Clomni push opens its conversation. false for the app's
    /// own pushes, which stay the app's to handle.
    @discardableResult
    public static func handlePush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let push = ProtocolJSON.clomniPush(userInfo) else { return false }
        let (initialized, disabled) = ClomniShared.state.read { ($0.initialized, $0.disabled) }
        guard initialized else {
            ClomniLog.error("handlePush: call Clomni.initialize first")
            return false
        }
        MainThread.run { ClomniRuntime.shared.coordinator?.handlePush(push) }
        return !disabled
    }

    /// For a notification that arrives while the app is open (`userNotificationCenter(_:willPresent:...)`, with
    /// `notification.request.content.userInfo`): false for a Clomni push while the messenger is open, which shows the
    /// message itself. true otherwise, and for the app's own pushes.
    public static func shouldShowForeground(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let push = ProtocolJSON.clomniPush(userInfo) else { return true }
        MainThread.run { ClomniRuntime.shared.coordinator?.pushArrived(push) }
        return !ClomniShared.state.read { $0.messengerOpen }
    }

    // MARK: - Unread count and events

    /// Called at once with the unread count, then on every change, until removed; for the app's own badge.
    @discardableResult
    public static func addUnreadCountListener(_ listener: @escaping @MainActor @Sendable (Int) -> Void) -> UUID {
        let token = UUID()
        MainThread.run { ClomniRuntime.shared.addUnreadCountListener(token, listener) }
        return token
    }

    public static func removeUnreadCountListener(_ token: UUID) {
        MainThread.run { ClomniRuntime.shared.removeUnreadCountListener(token) }
    }

    /// The messenger opened, with the `source` given to `present`.
    public static var onMessengerOpened: (@MainActor @Sendable (String?) -> Void)? {
        get { ClomniShared.state.read { $0.events.messengerOpened } }
        set { ClomniShared.state.write { $0.events.messengerOpened = newValue } }
    }

    public static var onMessengerClosed: (@MainActor @Sendable () -> Void)? {
        get { ClomniShared.state.read { $0.events.messengerClosed } }
        set { ClomniShared.state.write { $0.events.messengerClosed = newValue } }
    }

    /// A new conversation, with its id.
    public static var onConversationStarted: (@MainActor @Sendable (String) -> Void)? {
        get { ClomniShared.state.read { $0.events.conversationStarted } }
        set { ClomniShared.state.write { $0.events.conversationStarted = newValue } }
    }

    public static var onUnreadCountChanged: (@MainActor @Sendable (Int) -> Void)? {
        get { ClomniShared.state.read { $0.events.unreadCountChanged } }
        set { ClomniShared.state.write { $0.events.unreadCountChanged = newValue } }
    }

    /// A flow reached its end, with the flow's id.
    public static var onFlowCompleted: (@MainActor @Sendable (String) -> Void)? {
        get { ClomniShared.state.read { $0.events.flowCompleted } }
        set { ClomniShared.state.write { $0.events.flowCompleted = newValue } }
    }
}

/// The app's user, for `Clomni.loginUser`. Clomni knows the user by `userId`, else by `email`.
public struct ClomniUser: Sendable, Equatable {
    public var userId: String?
    public var email: String?
    public var phone: String?
    public var name: String?

    public init(userId: String? = nil, email: String? = nil, phone: String? = nil, name: String? = nil) {
        self.userId = userId
        self.email = email
        self.phone = phone
        self.name = name
    }

    var identity: UserIdentity {
        UserIdentity(userId: userId, email: email, phone: phone, name: name)
    }
}

/// For `Clomni.setTheme`.
public enum ClomniThemeMode: Sendable, Equatable {
    case system, light, dark

    var mode: MessengerConfig.Mode {
        switch self {
        case .system: return .system
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// How much the SDK writes to the system log, for `Clomni.setLogLevel`.
public enum ClomniLogLevel: Sendable, Equatable {
    case none
    /// A wrong api key or user_hash, a call before `initialize`, or something the app asked for that failed.
    case error
    /// Also what was dropped or could not be done. The default.
    case warning
    case info
    case debug

    var level: LogLevel? {
        switch self {
        case .none: return nil
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        case .debug: return .debug
        }
    }
}
