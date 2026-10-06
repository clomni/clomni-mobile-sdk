// Signatures only, copied from ios/api/ClomniMessenger.txt; nothing here runs.
import Foundation

public enum Clomni {
    public static let version: String = ""
    public static var onConversationStarted: (@MainActor @Sendable (String) -> Void)?
    public static var onFlowCompleted: (@MainActor @Sendable (String) -> Void)?
    public static var onLink: (@MainActor @Sendable (URL) -> Void)?
    public static var onMessengerClosed: (@MainActor @Sendable () -> Void)?
    public static var onMessengerOpened: (@MainActor @Sendable (String?) -> Void)?
    public static var onUnreadCountChanged: (@MainActor @Sendable (Int) -> Void)?

    public static func addUnreadCountListener(_ listener: @escaping @MainActor @Sendable (Int) -> Void) -> UUID { fatalError() }
    public static func dismiss() {}
    public static func handlePush(_ userInfo: [AnyHashable: Any]) -> Bool { fatalError() }
    public static func initialize(appId: String, apiKey: String, region: String = "eu") {}
    public static func isClomniPush(_ userInfo: [AnyHashable: Any]) -> Bool { fatalError() }
    public static func loginUnidentifiedUser() {}
    public static func loginUser(_ user: ClomniUser, userHash: String?) {}
    public static func logout() {}
    public static func present(source: String? = nil) {}
    public static func presentConversation(_ id: String) {}
    public static func presentNewConversation(source: String? = nil) {}
    public static func removeUnreadCountListener(_ token: UUID) {}
    public static func setBottomPadding(_ padding: Double) {}
    public static func setDeviceToken(_ token: Data) {}
    public static func setLanguage(_ language: String?) {}
    public static func setLauncherVisible(_ visible: Bool) {}
    public static func setLogLevel(_ level: ClomniLogLevel) {}
    public static func setSoundsEnabled(_ enabled: Bool) {}
    public static func setTheme(primaryColor: String? = nil, typeface: String? = nil, mode: ClomniThemeMode? = nil) {}
    public static func setTypeface(_ familyName: String?) {}
    public static func shouldShowForeground(_ userInfo: [AnyHashable: Any]) -> Bool { fatalError() }
    public static func startFlow(_ event: String, data: [String: Any] = [:], openMessenger: Bool = false, source: String? = nil) {}
    public static func updateUser(name: String? = nil, language: String? = nil, customAttributes: [String: Any]? = nil) {}
}

public enum ClomniLogLevel: Sendable, Equatable { case debug, error, info, none, warning }

public enum ClomniThemeMode: Sendable, Equatable { case system, light, dark }

public struct ClomniUser: Sendable, Equatable {
    public var userId: String?
    public var email: String?
    public var phone: String?
    public var name: String?

    public init(userId: String? = nil, email: String? = nil, phone: String? = nil, name: String? = nil) {}
}
