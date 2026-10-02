import Foundation
import XCTest
import ClomniProtocol
import ClomniCore
import ClomniPresentation
@testable import ClomniMessenger

/// The SDK below the facade, recording what it was asked.
actor FakeBackend: ClomniBackend {
    let baseURL: URL
    private(set) var calls: [String] = []
    private(set) var fields: [[String: JSONValue]] = []
    private var loggedIn = false
    private var unread = 0
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]
    private var failLogin: ClomniError?
    private var disabled = false

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    var isLoggedIn: Bool { loggedIn }
    var isAppDisabled: Bool { disabled }
    var unreadTotal: Int { unread }
    var config: MessengerConfig? { nil }
    nonisolated func cachedConfigFromDisk() -> MessengerConfig? { nil }

    func fail(_ error: ClomniError?, disabled: Bool = false) {
        failLogin = error
        self.disabled = disabled
    }

    func loginUnidentifiedUser() async throws {
        calls.append("loginUnidentifiedUser")
        if let failLogin { throw failLogin }
        loggedIn = true
    }

    func loginUser(_ user: UserIdentity, userHash: String?) async throws {
        calls.append("loginUser \(user.userId ?? "-") \(user.name ?? "-") \(userHash ?? "-")")
        if let failLogin { throw failLogin }
        loggedIn = true
    }

    func logout() async {
        calls.append("logout")
        loggedIn = false
    }

    func updateUser(_ fields: [String: JSONValue]) async throws -> MobileUser {
        calls.append("updateUser")
        if let failLogin { throw failLogin }
        self.fields.append(fields)
        return ProtocolJSON.parseUser(Data(#"{"id":"usr_5","anonymous":false}"#.utf8))!
    }

    func setDeviceToken(_ token: String, sandbox: Bool) async {
        calls.append("setDeviceToken \(token) \(sandbox ? "sandbox" : "production")")
    }

    func refreshConfig(language: String?) async -> MessengerConfig? {
        calls.append("config")
        return nil
    }

    func connect() async {
        calls.append("connect")
    }

    func draftConversation(openedFrom: String?) async -> String {
        calls.append("draftConversation \(openedFrom ?? "-")")
        return "draft_new"
    }

    func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                   openedFrom: String?) async throws -> Conversation? {
        calls.append("startFlow \(event) \(String(decoding: ProtocolJSON.encode(.object(data)), as: UTF8.self))")
        return ProtocolJSON.parseConversation(Data(#"{"id":"conv_flow","status":"bot","created_at":"2026-10-01T10:30:00Z"}"#.utf8))
    }

    func messages(in conversationId: String) async -> [Message] { [] }

    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func changeUnread(_ total: Int) {
        unread = total
        observers.values.forEach { $0(.unread(total: total)) }
    }
}

@MainActor
final class Renders: MessengerRenderer {
    var count = 0
    var typefaces: [String?] = []
    var overrides: [ThemeOverride] = []
    func render() { count += 1 }
    func setTypeface(_ family: String?) { typefaces.append(family) }
    func setThemeOverride(_ override: ThemeOverride) { overrides.append(override) }
}

final class Lines: @unchecked Sendable {
    private let lines = Locked<[String]>([])
    var all: [String] { lines.read { $0 } }
    func append(_ line: String) { lines.write { $0.append(line) } }
    func contains(_ text: String) -> Bool { all.contains { $0.contains(text) } }
}

@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// What the app was told, and on which thread.
@MainActor
final class Told {
    var lines: [String] = []
    var offMain = 0

    func note(_ line: String) {
        if !Thread.isMainThread { offMain += 1 }
        lines.append(line)
    }
}

/// The public facade over a fake SDK: every call from the app's side, as an app makes it.
@MainActor
final class FacadeTests: XCTestCase {
    private var backend: FakeBackend?
    private let renders = Renders()
    private let log = Lines()
    private var told = Told()

    override func setUp() async throws {
        told = Told()
        let log = log
        ClomniLog.handler = { level, line in log.append(ClomniLog.format(level, line)) }
        ClomniLog.level = .debug
        ClomniShared.state.write { $0 = ClomniShared.State() }
        let renders = renders
        ClomniRuntime.shared = ClomniRuntime(
            makeBackend: { [weak self] _, _, baseURL in
                let backend = FakeBackend(baseURL: baseURL)
                self?.backend = backend
                return backend
            },
            makeRenderer: { _, _ in renders },
            isSandbox: { false })
        let told = told
        Clomni.onMessengerOpened = { told.note("opened \($0 ?? "-")") }
        Clomni.onMessengerClosed = { told.note("closed") }
        Clomni.onConversationStarted = { told.note("started \($0)") }
        Clomni.onUnreadCountChanged = { told.note("unread \($0)") }
        Clomni.onFlowCompleted = { told.note("flow \($0)") }
    }

    override func tearDown() async throws {
        ClomniLog.reset()
        ClomniShared.state.write { $0 = ClomniShared.State() }
    }

    private var runtime: ClomniRuntime { ClomniRuntime.shared }

    private func calls() async -> [String] {
        await backend?.calls ?? []
    }

    /// Until the backend has been called with `call`: a detached task of utility priority makes it, which a busy
    /// Simulator may run a good while later. Gives up after 15 s.
    private func calls(including call: String) async -> [String] {
        for _ in 0..<1500 {
            let made = await calls()
            if made.contains(call) { return made }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await calls()
    }

    /// Lets the SDK's own tasks run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private var clomniPush: [AnyHashable: Any] { Self.clomniPushInfo() }

    nonisolated private static func clomniPushInfo() -> [AnyHashable: Any] { [
        "aps": ["alert": ["title": "Leyla · Apar", "body": "Balansınıza 2 AZN qaytarıldı."], "sound": "default",
                "badge": 1, "mutable-content": 1] as [String: Any],
        "clomni": "1", "type": "message", "conversation_id": "conv_5521", "message_id": "msg_f02",
        "title": "Leyla · Apar", "body": "Balansınıza 2 AZN qaytarıldı.", "unread_total": 1,
    ] }
    private let ownPush: [AnyHashable: Any] = ["aps": ["alert": "Sifarişiniz yoldadır"] as [String: Any], "order_id": 7]

    // MARK: - Before initialize

    func testCallsBeforeInitializeAreKeptOrRefused() async {
        let counts = Box<[Int]>([])
        Clomni.addUnreadCountListener { counts.value.append($0) }
        XCTAssertEqual(counts.value, [0], "called at once, initialize or not")
        Clomni.setLauncherVisible(true)
        Clomni.setBottomPadding(64)
        Clomni.setDeviceToken(Data([0xAB, 0x01]))
        Clomni.present(source: "profile_support")
        XCTAssertTrue(log.contains("[Clomni] error: present: call Clomni.initialize first"))
        XCTAssertFalse(Clomni.handlePush(clomniPush))
        XCTAssertTrue(log.contains("handlePush: call Clomni.initialize first"))
        XCTAssertTrue(Clomni.shouldShowForeground(clomniPush), "nothing is open")
        XCTAssertEqual(told.lines, [])

        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        let made = await calls(including: "setDeviceToken ab01 production")
        XCTAssertEqual(made, ["setDeviceToken ab01 production"])
        XCTAssertEqual(runtime.coordinator?.launcher?.bottomPadding, nil, "the launcher waits for the SDK to be ready")
        Clomni.loginUnidentifiedUser()
        await settle()
        XCTAssertEqual(runtime.coordinator?.launcher?.bottomPadding, 64)
    }

    func testInitializeOnceInTheRegion() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        let first = backend
        XCTAssertEqual(first?.baseURL.absoluteString, "https://app.clomni.ai/v1")
        Clomni.initialize(appId: "app_other", apiKey: "ios_other", region: "eu")
        XCTAssertTrue(first === backend)
        XCTAssertTrue(log.contains("[Clomni] warning: initialize was called before; the first call stays"))
        XCTAssertEqual(ClomniRuntime.baseURL(region: "EU").absoluteString, "https://app.clomni.ai/v1")
        XCTAssertEqual(ClomniRuntime.baseURL(region: "mars").absoluteString, "https://app.clomni.ai/v1")
        XCTAssertTrue(log.contains("[Clomni] error: unknown region \"mars\"; using eu"))
    }

    // MARK: - User

    func testLoginUpdateAndLogout() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        Clomni.loginUser(ClomniUser(userId: "5", email: "aysel@apar.az", name: "Aysel"), userHash: "a1b2")
        await settle()
        var made = await calls()
        XCTAssertEqual(made.first, "loginUser 5 Aysel a1b2")
        XCTAssertTrue(made.contains("connect"), "the coordinator starts after login")

        Clomni.updateUser(name: "Aysel Məmmədova", language: "az", customAttributes: ["plan": "premium", "rides": 18])
        await settle()
        let sent = await backend?.fields
        XCTAssertEqual(sent, [["name": "Aysel Məmmədova", "language": "az",
                               "custom_attributes": ["plan": "premium", "rides": 18]]])
        Clomni.updateUser()
        XCTAssertTrue(log.contains("[Clomni] warning: updateUser: nothing to change"))
        Clomni.updateUser(customAttributes: ["at": Date()])
        XCTAssertTrue(log.contains("[Clomni] error: updateUser: customAttributes hold something JSON cannot carry"))

        await backend?.changeUnread(3)
        await settle()
        Clomni.logout()
        await settle()
        made = await calls()
        XCTAssertEqual(made.filter { $0 == "updateUser" }.count, 1)
        XCTAssertEqual(made.last, "logout")
        XCTAssertEqual(told.lines, ["unread 3", "unread 0"])
    }

    func testFailuresAreLogged() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        await backend?.fail(.server(status: 403, error: nil))
        Clomni.loginUser(ClomniUser(userId: "5"), userHash: "WRONG")
        Clomni.updateUser(name: "Aysel")
        await settle()
        XCTAssertTrue(log.contains("[Clomni] error: login failed:"))
        XCTAssertTrue(log.contains("[Clomni] error: updateUser failed:"))
    }

    // MARK: - Opening

    func testOpeningAndClosingTellTheApp() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        let before = renders.count
        Clomni.present(source: "profile_support")
        XCTAssertEqual(runtime.coordinator?.route, .home)
        XCTAssertGreaterThan(renders.count, before, "UIKit is told")
        Clomni.presentConversation("conv_5521")
        XCTAssertEqual(runtime.coordinator?.route, .conversation("conv_5521"))
        Clomni.dismiss()
        XCTAssertNil(runtime.coordinator?.route)
        Clomni.presentNewConversation(source: "help_button")
        await settle()
        XCTAssertEqual(runtime.coordinator?.route, .conversation("draft_new"), "created with its first message")
        Clomni.dismiss()

        Clomni.startFlow("ride_problem", data: ["ride_id": "R-77", "minutes": 18], openMessenger: true, source: "ride")
        await settle()
        XCTAssertEqual(runtime.coordinator?.route, .conversation("conv_flow"))
        let made = await calls()
        XCTAssertTrue(made.contains(#"startFlow ride_problem {"minutes":18,"ride_id":"R-77"}"#), "\(made)")
        Clomni.startFlow("payment_failed", data: ["when": Date()])
        XCTAssertTrue(log.contains("[Clomni] error: startFlow: data holds something JSON cannot carry"))

        XCTAssertEqual(told.lines, ["opened profile_support", "closed", "opened help_button", "closed",
                                    "started conv_flow", "opened ride"])
        XCTAssertEqual(told.offMain, 0)
    }

    func testTypefaceReachesTheScreensBeforeAndAfterInitialize() async {
        Clomni.setTypeface("Montserrat")
        XCTAssertEqual(renders.typefaces, [], "no screens yet")
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        XCTAssertEqual(renders.typefaces, ["Montserrat"])
        Clomni.setTypeface(nil)
        XCTAssertEqual(renders.typefaces, ["Montserrat", nil])
    }

    func testSetThemeOverridesThePanel() async {
        Clomni.setTheme(primaryColor: "#0A66C2", mode: .dark)
        XCTAssertEqual(renders.overrides, [], "no screens yet")
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        XCTAssertEqual(renders.overrides, [ThemeOverride(primaryColor: "#0A66C2", mode: .dark)])
        Clomni.setTheme(typeface: "Montserrat")
        XCTAssertEqual(renders.overrides.last, ThemeOverride(), "each call replaces the last")
        XCTAssertEqual(renders.typefaces, ["Montserrat"])
        Clomni.setTheme(primaryColor: "blue", mode: .system)
        XCTAssertEqual(renders.overrides.last, ThemeOverride(primaryColor: nil, mode: .system))
        XCTAssertTrue(log.contains("[Clomni] error: setTheme: primaryColor \"blue\" is not #RRGGBB"))
        XCTAssertEqual(ClomniThemeMode.light.mode, .light)
    }

    func testLauncher() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        Clomni.loginUnidentifiedUser()
        await settle()
        XCTAssertNil(runtime.coordinator?.launcher, "off by default")
        Clomni.setLauncherVisible(true)
        Clomni.setBottomPadding(49)
        XCTAssertEqual(runtime.coordinator?.launcher?.bottomPadding, 49)
        Clomni.setLauncherVisible(false)
        XCTAssertNil(runtime.coordinator?.launcher)
    }

    // MARK: - Threads

    /// From any thread the calls run on the main thread, in order, and the app hears on the main thread.
    func testCallsFromAnotherThread() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        let done = expectation(description: "calls made")
        // The listener hears again on every change (the push below changes the count): only the first one counts.
        done.assertForOverFulfill = false
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            Clomni.present(source: "first")
            Clomni.dismiss()
            Clomni.present(source: "second")
            Clomni.addUnreadCountListener { _ in
                XCTAssertTrue(Thread.isMainThread)
                done.fulfill()
            }
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(told.lines, ["opened first", "closed", "opened second"])
        XCTAssertEqual(told.offMain, 0)
        XCTAssertEqual(runtime.coordinator?.route, .home)

        // The push questions answer at once on any thread, from what the main thread last saw.
        let answered = expectation(description: "push answered")
        DispatchQueue.global().async {
            let push = Self.clomniPushInfo()
            XCTAssertFalse(Clomni.shouldShowForeground(push), "the messenger is open")
            XCTAssertTrue(Clomni.handlePush(push))
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: 5)
        await settle()
        XCTAssertEqual(runtime.coordinator?.route, .conversation("conv_5521"))
    }

    // MARK: - Push

    func testPushes() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        XCTAssertTrue(Clomni.isClomniPush(clomniPush))
        XCTAssertFalse(Clomni.isClomniPush(ownPush))

        // The app's own pushes stay the app's, without a word in the log.
        XCTAssertFalse(Clomni.handlePush(ownPush))
        XCTAssertTrue(Clomni.shouldShowForeground(ownPush))
        XCTAssertEqual(log.all, [])

        XCTAssertTrue(Clomni.shouldShowForeground(clomniPush), "closed: shown")
        XCTAssertEqual(told.lines, ["unread 1"], "its count reaches the app")
        XCTAssertTrue(Clomni.handlePush(clomniPush))
        XCTAssertEqual(runtime.coordinator?.route, .conversation("conv_5521"))
        XCTAssertEqual(runtime.coordinator?.source, "push")
        XCTAssertFalse(Clomni.shouldShowForeground(clomniPush), "open: not shown")
        Clomni.present()
        XCTAssertTrue(Clomni.shouldShowForeground(ownPush), "the app's own is still shown")
        XCTAssertFalse(Clomni.shouldShowForeground(clomniPush), "Home is open too")

        // A Clomni push this version cannot read: shown as it came, nothing opens, a line in the log.
        Clomni.dismiss()
        let later: [AnyHashable: Any] = ["aps": ["alert": "Sorğu"] as [String: Any], "clomni": "1", "type": "survey"]
        XCTAssertTrue(Clomni.isClomniPush(later))
        XCTAssertFalse(Clomni.handlePush(later))
        XCTAssertTrue(Clomni.shouldShowForeground(later))
        XCTAssertNil(runtime.coordinator?.route)
        XCTAssertTrue(log.contains("[Clomni] warning: push"))

        Clomni.setDeviceToken(Data([0x00, 0xFF]))
        let made = await calls(including: "setDeviceToken 00ff production")
        XCTAssertTrue(made.contains("setDeviceToken 00ff production"))
    }

    func testASwitchedOffInboxOpensNothingFromAPush() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        await backend?.fail(.server(status: 403, error: nil), disabled: true)
        Clomni.present()
        await runtime.coordinator?.prepare()
        XCTAssertNil(runtime.coordinator?.route)
        XCTAssertFalse(Clomni.handlePush(clomniPush))
        XCTAssertNil(runtime.coordinator?.route)
    }

    // MARK: - Listeners and settings

    func testUnreadListeners() async {
        Clomni.initialize(appId: "app_8x2k0001", apiKey: "ios_sdk-test")
        Clomni.loginUnidentifiedUser()
        await settle()
        let first = Box<[Int]>([])
        let second = Box<[Int]>([])
        let token = Clomni.addUnreadCountListener { first.value.append($0) }
        Clomni.addUnreadCountListener { second.value.append($0) }
        await backend?.changeUnread(2)
        await settle()
        Clomni.removeUnreadCountListener(token)
        await backend?.changeUnread(5)
        await settle()
        XCTAssertEqual(first.value, [0, 2])
        XCTAssertEqual(second.value, [0, 2, 5])
        XCTAssertEqual(told.lines, ["unread 2", "unread 5"])
    }

    func testLogLevel() {
        Clomni.setLogLevel(.none)
        XCTAssertNil(ClomniLog.level)
        Clomni.present()
        XCTAssertEqual(log.all, [])
        let levels: [(ClomniLogLevel, LogLevel)] = [(.error, .error), (.warning, .warning), (.info, .info), (.debug, .debug)]
        for (level, expected) in levels {
            Clomni.setLogLevel(level)
            XCTAssertEqual(ClomniLog.level, expected)
        }
    }

    func testEventsCanBeReadBack() {
        XCTAssertNotNil(Clomni.onMessengerOpened)
        Clomni.onMessengerOpened = nil
        Clomni.onMessengerClosed = nil
        Clomni.onConversationStarted = nil
        Clomni.onUnreadCountChanged = nil
        Clomni.onFlowCompleted = nil
        XCTAssertNil(Clomni.onMessengerOpened)
        XCTAssertNil(Clomni.onMessengerClosed)
        XCTAssertNil(Clomni.onConversationStarted)
        XCTAssertNil(Clomni.onUnreadCountChanged)
        XCTAssertNil(Clomni.onFlowCompleted)
    }

    func testTheEngineIsTheBackend() {
        let backend = ClomniRuntime.engine(appId: "app_test", apiKey: "ios_sdk-test", baseURL: ClomniRuntime.baseURL(region: "eu"))
        XCTAssertTrue(backend is ClomniEngine)
        let screens = ClomniRuntime.screens(backend, MessengerCoordinator(session: backend))
        #if canImport(UIKit) && canImport(SwiftUI)
        XCTAssertTrue(screens is UIKitMessenger)
        #else
        XCTAssertNil(screens, "no UIKit here")
        #endif
    }
}
