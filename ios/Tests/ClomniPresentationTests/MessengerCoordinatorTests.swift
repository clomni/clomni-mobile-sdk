import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore
@testable import ClomniPresentation

/// An SDK below the coordinator whose answers the test sets.
actor FakeSession: MessengerSession {
    var loggedIn = false
    var disabled = false
    var disableOnLogin = false
    var offline = false
    var unread = 0
    var cachedConfig: MessengerConfig?
    var freshConfig: MessengerConfig? = Fixture.aparConfig
    var flowBound = true
    var stored: [String: [Message]] = [:]
    var calls: [String] = []
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]

    var isLoggedIn: Bool { loggedIn }
    var isAppDisabled: Bool { disabled }
    var unreadTotal: Int { unread }
    var config: MessengerConfig? { cachedConfig }

    func set(loggedIn: Bool = false, disabled: Bool = false, disableOnLogin: Bool = false, unread: Int = 0,
             cached: MessengerConfig? = nil, fresh: MessengerConfig? = Fixture.aparConfig,
             flowBound: Bool = true) {
        self.loggedIn = loggedIn
        self.disabled = disabled
        self.disableOnLogin = disableOnLogin
        self.unread = unread
        cachedConfig = cached
        freshConfig = fresh
        self.flowBound = flowBound
    }

    func loginUnidentifiedUser() async throws {
        calls.append("login")
        if offline { throw ClomniError.network("offline") }
        if disableOnLogin {
            disabled = true
            throw ClomniError.server(status: 403, error: nil)
        }
        loggedIn = true
    }

    func refreshConfig(language: String?) async -> MessengerConfig? {
        calls.append("config")
        if freshConfig != nil { cachedConfig = freshConfig }
        return cachedConfig
    }

    func goOffline(_ offline: Bool) {
        self.offline = offline
    }

    func connect() async { calls.append("connect") }

    func draftConversation(openedFrom: String?) async -> String {
        calls.append("draft \(openedFrom ?? "-")")
        return "draft_\(calls.count)"
    }

    func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                   openedFrom: String?) async throws -> Conversation? {
        calls.append("flow \(event) \(openMessenger) \(openedFrom ?? "-")")
        return flowBound ? Fixture.conversation(status: "bot") : nil
    }

    func messages(in conversationId: String) async -> [Message] { stored[conversationId] ?? [] }

    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func push(_ change: ClomniChange, unread: Int? = nil, messages: [Message]? = nil, in id: String = "conv_5521") {
        if let unread { self.unread = unread }
        if let messages { stored[id] = messages }
        observers.values.forEach { $0(change) }
    }

    var observerCount: Int { observers.count }
}

final class CapturedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    func contains(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.contains { $0.contains(text) }
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty
    }
}

/// What the app was told.
@MainActor
final class Heard {
    var opened: [String?] = []
    var closed = 0
    var started: [String] = []
    var unread: [Int] = []
    var flows: [String] = []

    func listen(to coordinator: MessengerCoordinator) {
        coordinator.events.messengerOpened = { [weak self] in self?.opened.append($0) }
        coordinator.events.messengerClosed = { [weak self] in self?.closed += 1 }
        coordinator.events.conversationStarted = { [weak self] in self?.started.append($0) }
        coordinator.events.unreadCountChanged = { [weak self] in self?.unread.append($0) }
        coordinator.events.flowCompleted = { [weak self] in self?.flows.append($0) }
    }
}

@MainActor
final class MessengerCoordinatorTests: XCTestCase {
    private let session = FakeSession()
    private let heard = Heard()
    private let log = CapturedLog()

    override func setUp() async throws {
        let log = log
        ClomniLog.handler = { _, line in log.append(line) }
        ClomniLog.level = .debug
    }

    override func tearDown() async throws {
        ClomniLog.reset()
    }

    private func coordinator() -> MessengerCoordinator {
        let coordinator = MessengerCoordinator(session: session, language: "az")
        heard.listen(to: coordinator)
        return coordinator
    }

    private func calls() async -> [String] { await session.calls }

    /// Brief 7.2, "Bitdi": with the launcher off, the app shows no Clomni element at all.
    func testNothingShowsUntilTheAppAsks() async {
        await session.set(loggedIn: true, cached: Fixture.aparConfig)
        let messenger = coordinator()
        XCTAssertFalse(messenger.wantsAnyView)
        await messenger.start()
        XCTAssertEqual(messenger.readiness, .ready)
        XCTAssertNil(messenger.launcher, "Apar's config has launcher.visible false")
        XCTAssertNil(messenger.route)
        XCTAssertFalse(messenger.wantsAnyView, "no overlay, no window, nothing")
        let made = await calls()
        XCTAssertEqual(made, ["connect", "config"])
    }

    func testTheLauncherRule() async throws {
        let messenger = coordinator()
        messenger.setLauncherVisible(true)
        XCTAssertNil(messenger.launcher, "not before the SDK is ready")
        await session.set(loggedIn: true, unread: 3)
        await messenger.start()
        XCTAssertEqual(messenger.launcher, LauncherState(side: .right, bottomPadding: 20, badge: "3",
                                                         accessibilityLabel: "Bizə mesaj göndərin, Oxunmamış mesaj var"))
        XCTAssertTrue(messenger.wantsAnyView)
        messenger.setBottomPadding(64)
        XCTAssertEqual(messenger.launcher?.bottomPadding, 64)
        messenger.present()
        XCTAssertNil(messenger.launcher, "hidden while the messenger is open")
        messenger.dismiss()
        XCTAssertNotNil(messenger.launcher)
        messenger.setLauncherVisible(false)
        XCTAssertNil(messenger.launcher)
        XCTAssertFalse(messenger.wantsAnyView)

        // The panel can turn it on, on the left; the app's choice wins over the panel's.
        let panelOn = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Apar","primary_color":"#1F9D63"},"theme":{"launcher":{"enabled":true,"position":"left","bottom_padding":0}}}
            """##.utf8)))
        await session.set(loggedIn: true, unread: 120, cached: panelOn, fresh: panelOn)
        let fromPanel = coordinator()
        await fromPanel.start()
        XCTAssertEqual(fromPanel.launcher?.side, .left)
        XCTAssertEqual(fromPanel.launcher?.bottomPadding, 0)
        XCTAssertEqual(fromPanel.launcher?.badge, "99+")
        fromPanel.setLauncherVisible(false)
        XCTAssertNil(fromPanel.launcher)
    }

    func testPresentingAndDismissing() async {
        let messenger = coordinator()
        XCTAssertTrue(messenger.present(source: "profile_support"))
        XCTAssertEqual(messenger.route, .home)
        XCTAssertEqual(messenger.source, "profile_support")
        XCTAssertTrue(messenger.wantsAnyView)
        // Opening a conversation while open is a move, not a second opening.
        messenger.presentConversation("conv_9", source: "push")
        XCTAssertEqual(messenger.route, .conversation("conv_9"))
        XCTAssertEqual(messenger.source, "profile_support")
        messenger.navigate(to: .home)
        XCTAssertEqual(messenger.route, .home)
        messenger.dismiss()
        messenger.dismiss()
        messenger.navigate(to: .home)
        XCTAssertNil(messenger.route, "navigating needs an open messenger")
        XCTAssertEqual(heard.opened, ["profile_support"])
        XCTAssertEqual(heard.closed, 1)
        XCTAssertTrue(messenger.presentConversation("conv_9", source: "push"))
        XCTAssertEqual(heard.opened, ["profile_support", "push"])
    }

    /// Opening before anyone logged in: an anonymous visitor, then the config, while the screens show skeletons.
    func testPreparingLogsInAVisitorOnlyWhenNeeded() async {
        let messenger = coordinator()
        messenger.present()
        let ready = await messenger.prepare()
        XCTAssertTrue(ready)
        XCTAssertEqual(messenger.readiness, .ready)
        XCTAssertEqual(messenger.config?.brand.name, "Apar")
        await messenger.prepare()
        let made = await calls()
        XCTAssertEqual(made, ["login", "connect", "config", "connect", "config"])
    }

    /// 403 app_disabled: present() does nothing and says so in the log.
    func testASwitchedOffInboxOpensNothing() async {
        await session.set(disableOnLogin: true)
        let messenger = coordinator()
        messenger.setLauncherVisible(true)
        XCTAssertTrue(messenger.present(), "not known yet")
        let ready = await messenger.prepare()
        XCTAssertFalse(ready)
        XCTAssertEqual(messenger.readiness, .disabled)
        XCTAssertNil(messenger.route, "the half-open messenger closes")
        XCTAssertFalse(messenger.present())
        XCTAssertNil(messenger.route)
        XCTAssertNil(messenger.launcher)
        XCTAssertFalse(messenger.wantsAnyView)
        let none = await messenger.presentNewConversation()
        XCTAssertNil(none)
        let noFlow = await messenger.startFlow("payment_failed", data: [:], openMessenger: true)
        XCTAssertNil(noFlow)
        XCTAssertTrue(log.contains("switched off in Clomni: present() does nothing"))

        await session.set(loggedIn: true, disabled: true)
        let known = coordinator()
        await known.start()
        XCTAssertEqual(known.readiness, .disabled)
        XCTAssertFalse(known.present())
    }

    /// A new conversation is a draft until its first message: opening and closing asks the server for nothing, and
    /// the app hears onConversationStarted when the server has created it.
    func testANewConversationCarriesTheSource() async throws {
        await session.set(loggedIn: true)
        let messenger = coordinator()
        await messenger.prepare()
        let before = await calls()
        let id = await messenger.presentNewConversation(source: "ride_screen")
        let draft = try XCTUnwrap(id)
        XCTAssertEqual(messenger.route, .conversation(draft))
        XCTAssertEqual(heard.opened, ["ride_screen"])
        XCTAssertTrue(heard.started.isEmpty, "nothing exists yet")
        var made = await calls()
        XCTAssertEqual(Array(made.dropFirst(before.count)), ["draft ride_screen"], "no other call")

        await session.push(.conversationCreated(draft: draft, conversationId: "conv_5521"))
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(heard.started, ["conv_5521"])

        messenger.dismiss()
        let second = await messenger.presentNewConversation()
        XCTAssertNotNil(second)
        messenger.dismiss()
        made = await calls()
        XCTAssertEqual(made.last, "draft -")
        XCTAssertEqual(heard.started, ["conv_5521"], "opened and closed: no conversation")
    }

    func testStartingAFlow() async {
        await session.set(loggedIn: true)
        let messenger = coordinator()
        let quiet = await messenger.startFlow("payment_failed", data: ["order_id": "A-1042"], openMessenger: false)
        XCTAssertEqual(quiet, "conv_5521")
        XCTAssertNil(messenger.route, "open_messenger false: only a push or the badge will tell")
        let shown = await messenger.startFlow("ride_problem", data: [:], openMessenger: true, source: "ride_screen")
        XCTAssertEqual(shown, "conv_5521")
        XCTAssertEqual(messenger.route, .conversation("conv_5521"))
        XCTAssertEqual(heard.started, ["conv_5521", "conv_5521"])
        let made = await calls()
        XCTAssertEqual(made.filter { $0.hasPrefix("flow") },
                       ["flow payment_failed false -", "flow ride_problem true ride_screen"])

        await session.set(loggedIn: true, flowBound: false)
        let unbound = await messenger.startFlow("nothing_bound", data: [:], openMessenger: true)
        XCTAssertNil(unbound)
    }

    /// Brief 7.2 says no empty screen; with no network at a first launch it is not endless skeletons either.
    func testAFailedPreparationOffersARetry() async {
        await session.goOffline(true)
        let messenger = coordinator()
        var states: [Bool] = []
        messenger.onChange = { states.append(messenger.preparationFailed) }
        XCTAssertTrue(messenger.present())
        let ready = await messenger.prepare()
        XCTAssertFalse(ready)
        XCTAssertTrue(messenger.preparationFailed)
        XCTAssertEqual(messenger.readiness, .notReady)
        XCTAssertEqual(messenger.route, .home, "the messenger stays open, offering Yenidən cəhd et")
        XCTAssertTrue(log.contains("messenger cannot open"))

        await session.goOffline(false)
        let again = await messenger.prepare()
        XCTAssertTrue(again)
        XCTAssertFalse(messenger.preparationFailed)
        XCTAssertEqual(messenger.readiness, .ready)
        // Opened, failed, skeletons again while it tries, ready.
        XCTAssertEqual(states, [false, true, false, false])
    }

    func testUnreadCount() async throws {
        await session.set(loggedIn: true, unread: 2)
        let messenger = coordinator()
        var counts: [Int] = []
        let token = messenger.addUnreadCountListener { counts.append($0) }
        XCTAssertEqual(counts, [0], "called at once")
        await messenger.start()
        await session.push(.unread(total: 5), unread: 5)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(counts, [0, 2, 5])
        XCTAssertEqual(heard.unread, [2, 5])
        messenger.removeUnreadCountListener(token)
        await session.push(.unread(total: 0), unread: 0)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(counts, [0, 2, 5])
        XCTAssertEqual(heard.unread, [2, 5, 0])
        XCTAssertEqual(messenger.unreadTotal, 0)
        await messenger.start()
        let observers = await session.observerCount
        XCTAssertEqual(observers, 1, "listens once")
    }

    /// A message from a flow's END node completes the flow; ENDs already there when first seen are history.
    func testFlowCompleted() async throws {
        await session.set(loggedIn: true)
        let messenger = coordinator()
        await messenger.start()
        let old = Fixture.message("50-apar-end.json", ["id": "msg_old_end"])
        await session.push(.messages(conversationId: "conv_5521"), messages: [old])
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(heard.flows.isEmpty)
        let step = Fixture.message("12-apar-level4-handoff.json")
        let end = Fixture.message("50-apar-end.json")
        await session.push(.messages(conversationId: "conv_5521"), messages: [old, step, end])
        await session.push(.messages(conversationId: "conv_5521"), messages: [old, step, end])
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(heard.flows, ["flw_apar_az"])
        await session.set(loggedIn: true, cached: Fixture.minimalConfig)
        await session.push(.config)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(messenger.config?.brand.name, "Clomni, Inc.")
    }

    func testLoggingOutHidesEverything() async {
        await session.set(loggedIn: true, unread: 4)
        let messenger = coordinator()
        messenger.setLauncherVisible(true)
        await messenger.start()
        messenger.present()
        messenger.loggedOut()
        XCTAssertNil(messenger.route)
        XCTAssertEqual(messenger.readiness, .notReady)
        XCTAssertEqual(messenger.unreadTotal, 0)
        XCTAssertEqual(heard.unread, [4, 0])
        XCTAssertEqual(heard.closed, 1)
        XCTAssertFalse(messenger.wantsAnyView)
    }

    // MARK: - Push

    /// What APNs hands the app: the alert in `aps`, the Clomni keys next to it (brief 6.5).
    private func push(_ conversation: String = "conv_5521", unread: Int? = 2) -> PushPayload {
        var userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Leyla · Apar", "body": "Balansınıza 2 AZN qaytarıldı."], "sound": "default",
                    "badge": 2, "mutable-content": 1] as [String: Any],
            "clomni": "1", "type": "message", "conversation_id": conversation, "message_id": "msg_f02",
            "title": "Leyla · Apar", "body": "Balansınıza 2 AZN qaytarıldı.", "avatar_url": "https://app.clomni.ai/a/l.png",
        ]
        if let unread { userInfo["unread_total"] = unread }
        return ProtocolJSON.clomniPush(userInfo)!
    }

    func testATapOnAPushOpensItsConversation() async {
        await session.set(loggedIn: true)
        let messenger = coordinator()
        await messenger.start()
        var counts: [Int] = []
        messenger.addUnreadCountListener { counts.append($0) }

        XCTAssertTrue(messenger.handlePush(push()))
        XCTAssertEqual(messenger.route, .conversation("conv_5521"))
        XCTAssertEqual(messenger.source, "push")
        XCTAssertEqual(heard.opened, ["push"])
        XCTAssertEqual(counts, [0, 2])
        XCTAssertEqual(heard.unread, [2])

        // Already open: the messenger moves to the push's conversation, still opened once.
        messenger.navigate(to: .home)
        XCTAssertTrue(messenger.handlePush(push("conv_7", unread: nil)))
        XCTAssertEqual(messenger.route, .conversation("conv_7"))
        XCTAssertEqual(heard.opened, ["push"])
        XCTAssertEqual(counts, [0, 2], "no count in the push, no change")
    }

    /// Brief 4.4 and 8 · 5.5: while the messenger is open, on any screen, a Clomni push is not shown.
    func testForegroundSuppression() async {
        await session.set(loggedIn: true)
        let messenger = coordinator()
        await messenger.start()
        XCTAssertTrue(messenger.showsForegroundPushes, "messenger closed")
        messenger.pushArrived(push(unread: 3))
        XCTAssertEqual(heard.unread, [3], "the count reaches the app")
        messenger.present()
        XCTAssertFalse(messenger.showsForegroundPushes, "Home")
        messenger.navigate(to: .conversation("conv_5521"))
        XCTAssertFalse(messenger.showsForegroundPushes)
        messenger.pushArrived(push(unread: 3))
        messenger.pushArrived(push(unread: nil))
        messenger.pushArrived(push(unread: 4))
        messenger.dismiss()
        XCTAssertTrue(messenger.showsForegroundPushes)
        XCTAssertEqual(heard.unread, [3, 4])
    }

    func testASwitchedOffInboxOpensNothingFromAPush() async {
        await session.set(loggedIn: true, disabled: true)
        let messenger = coordinator()
        await messenger.start()
        XCTAssertFalse(messenger.handlePush(push()))
        XCTAssertNil(messenger.route)
        XCTAssertEqual(heard.opened, [])
    }

    func testTheEngineIsAMessengerSession() {
        let engine: MessengerSession = ClomniEngine(appId: "app_test", apiKey: "ios_sdk-test")
        XCTAssertNotNil(engine)
    }
}
