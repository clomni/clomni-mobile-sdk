import ClomniMessenger
import Foundation

/// What the React Native module does on iOS. RCTClomni.mm (Objective-C++, which the New Architecture needs) cannot
/// call the SDK's Swift API, so it calls this: each call goes to `Clomni`, and the SDK's events go back to JS as
/// `{name, count?, text?}` through `emit`. The SDK takes calls from any thread; the module's queue is not the main one.
@objc(ClomniBridge)
public final class ClomniBridge: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var emitter: ((NSDictionary) -> Void)?
    private var unread = 0
    private var unreadListener: UUID?

    @objc public init(emit: @escaping (NSDictionary) -> Void) {
        emitter = emit
        super.init()
        Clomni.onMessengerOpened = { [weak self] source in self?.send("messengerOpened", text: source) }
        Clomni.onMessengerClosed = { [weak self] in self?.send("messengerClosed") }
        Clomni.onConversationStarted = { [weak self] id in self?.send("conversationStarted", text: id) }
        Clomni.onFlowCompleted = { [weak self] flowId in self?.send("flowCompleted", text: flowId) }
        unreadListener = Clomni.addUnreadCountListener { [weak self] count in
            guard let self else { return }
            self.locked { self.unread = count }
            self.send("unreadCountChanged", count: count)
        }
    }

    /// The module is going away (a reload): its events stop.
    @objc public func invalidate() {
        let listener = locked { () -> UUID? in
            emitter = nil
            return unreadListener
        }
        if let listener { Clomni.removeUnreadCountListener(listener) }
        Clomni.onMessengerOpened = nil
        Clomni.onMessengerClosed = nil
        Clomni.onConversationStarted = nil
        Clomni.onFlowCompleted = nil
    }

    @objc(setupWithAppId:apiKey:region:)
    public func setup(appId: String, apiKey: String, region: String) {
        Clomni.initialize(appId: appId, apiKey: apiKey, region: region)
    }

    @objc(loginUser:userHash:)
    public func loginUser(_ user: NSDictionary, userHash: String?) {
        Clomni.loginUser(ClomniUser(userId: user["userId"] as? String, email: user["email"] as? String,
                                    phone: user["phone"] as? String, name: user["name"] as? String),
                         userHash: userHash)
    }

    @objc public func loginUnidentifiedUser() {
        Clomni.loginUnidentifiedUser()
    }

    @objc(updateUserWithName:language:customAttributes:)
    public func updateUser(name: String?, language: String?, customAttributes: NSDictionary?) {
        Clomni.updateUser(name: name, language: language, customAttributes: customAttributes as? [String: Any])
    }

    @objc public func logout() {
        Clomni.logout()
    }

    @objc(setLogLevel:)
    public func setLogLevel(_ level: String) {
        let levels: [String: ClomniLogLevel] = ["none": .none, "error": .error, "warning": .warning, "info": .info,
                                                 "debug": .debug]
        guard let known = levels[level] else { return NSLog("[Clomni] setLogLevel: unknown level \"%@\"", level) }
        Clomni.setLogLevel(known)
    }

    @objc(setTypeface:)
    public func setTypeface(_ familyName: String?) {
        Clomni.setTypeface(familyName)
    }

    @objc(presentWithSource:)
    public func present(source: String?) {
        Clomni.present(source: source)
    }

    @objc(presentNewConversationWithSource:)
    public func presentNewConversation(source: String?) {
        Clomni.presentNewConversation(source: source)
    }

    @objc(presentConversation:)
    public func presentConversation(_ conversationId: String) {
        Clomni.presentConversation(conversationId)
    }

    @objc public func dismiss() {
        Clomni.dismiss()
    }

    @objc(startFlow:data:openMessenger:source:)
    public func startFlow(_ event: String, data: NSDictionary, openMessenger: Bool, source: String?) {
        Clomni.startFlow(event, data: data as? [String: Any] ?? [:], openMessenger: openMessenger, source: source)
    }

    @objc(setLauncherVisible:)
    public func setLauncherVisible(_ visible: Bool) {
        Clomni.setLauncherVisible(visible)
    }

    @objc(setBottomPadding:)
    public func setBottomPadding(_ padding: Double) {
        Clomni.setBottomPadding(padding)
    }

    /// The APNs device token as React Native's push libraries give it: hex text.
    @objc(setDeviceToken:)
    public func setDeviceToken(_ hex: String) {
        guard let token = Self.data(hex: hex) else {
            return NSLog("[Clomni] setDeviceToken: not an APNs token in hex; nothing registered")
        }
        Clomni.setDeviceToken(token)
    }

    @objc(handlePush:)
    public func handlePush(_ data: NSDictionary) {
        Clomni.handlePush(data as? [AnyHashable: Any] ?? [:])
    }

    @objc(shouldShowForeground:)
    public func shouldShowForeground(_ data: NSDictionary) -> Bool {
        Clomni.shouldShowForeground(data as? [AnyHashable: Any] ?? [:])
    }

    @objc public func unreadCount() -> Int {
        locked { unread }
    }

    /// "ab01…" → bytes; nil for anything else.
    static func data(hex: String) -> Data? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return Data(bytes)
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return digit - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private func send(_ name: String, count: Int? = nil, text: String? = nil) {
        var event: [String: Any] = ["name": name]
        if let count { event["count"] = count }
        if let text { event["text"] = text }
        let emit = locked { emitter }
        emit?(event as NSDictionary)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
