import Foundation
import XCTest
import ClomniProtocol
import ClomniCore
@testable import ClomniPresentation

/// A data source whose answers the test sets.
actor FakeSource: MessengerDataSource {
    var cached: MessengerConfig?
    var fresh: MessengerConfig?
    var list: [Conversation] = []
    var unread = 0
    var conversationsFail = false
    var startFails = false
    var starts = 0
    private var handler: (@Sendable (ClomniChange) -> Void)?

    var config: MessengerConfig? { cached }
    var unreadTotal: Int { unread }

    func refreshConfig(language: String?) async -> MessengerConfig? {
        if fresh != nil { cached = fresh }
        return cached
    }

    func conversations() async -> [Conversation] { list }

    func refreshConversations() async throws {
        if conversationsFail { throw ClomniError.network("offline") }
    }

    func startConversation(openedFrom: String?) async throws -> Conversation {
        starts += 1
        // Long enough for a second tap to arrive meanwhile.
        try await Task.sleep(nanoseconds: 20_000_000)
        if startFails { throw ClomniError.network("offline") }
        let conversation = Fixture.conversation("conv_\(starts)", message: "09-apar-level1-A.json")
        list.insert(conversation, at: 0)
        return conversation
    }

    func setChangeHandler(_ handler: @escaping @Sendable (ClomniChange) -> Void) {
        self.handler = handler
    }

    func set(cached: MessengerConfig? = nil, fresh: MessengerConfig? = nil, list: [Conversation]? = nil,
             conversationsFail: Bool = false, startFails: Bool = false) {
        self.cached = cached
        self.fresh = fresh
        if let list { self.list = list }
        self.conversationsFail = conversationsFail
        self.startFails = startFails
    }

    /// What the engine does when a socket event arrives.
    func push(unread: Int, _ change: ClomniChange) {
        self.unread = unread
        handler?(change)
    }
}

@MainActor
final class HomeControllerTests: XCTestCase {
    private let source = FakeSource()
    private var renders = 0

    private func controller(user: String? = "Aysel") -> HomeController {
        let controller = HomeController(source: source, language: "az", userName: user,
                                        timeZone: TimeZone(identifier: "UTC")!,
                                        now: { Date(timeIntervalSince1970: 1_790_850_720) })
        controller.onChange = { [weak self] in self?.renders += 1 }
        return controller
    }

    func testStartsAsASkeleton() {
        let home = controller()
        XCTAssertEqual(home.home.phase, .loading)
        XCTAssertEqual(home.messages.phase, .loading)
        XCTAssertEqual(home.home.header.greeting, "Salam, Aysel 👋")
    }

    func testShowsTheCacheThenTheServersAnswer() async {
        await source.set(cached: Fixture.minimalConfig, fresh: Fixture.aparConfig,
                         list: [Fixture.conversation("conv_1", message: "02-text-operator-markdown.json")])
        let home = controller()
        await home.load()
        XCTAssertEqual(renders, 2, "once from the cache, once after the refresh")
        XCTAssertEqual(home.home.phase, .ready)
        XCTAssertEqual(home.home.header.brandName, "Apar")
        XCTAssertEqual(home.config?.brand.primaryColor, "#1F9D63")
        XCTAssertEqual(home.home.recent?.row.detail, "Leyla · 2 dəq")
        XCTAssertEqual(home.messages.rows.count, 1)
    }

    func testNothingCachedAndNoServerIsAnErrorWithRetry() async {
        await source.set(conversationsFail: true)
        let home = controller()
        await home.load()
        XCTAssertEqual(home.home.phase, .failed)
        XCTAssertEqual(home.home.failure?.retry, "Yenidən cəhd et")
        XCTAssertEqual(home.messages.phase, .failed)

        await source.set(fresh: Fixture.aparConfig)
        await home.retry()
        XCTAssertEqual(home.home.phase, .ready)
        XCTAssertEqual(home.messages.phase, .ready)
        XCTAssertEqual(home.messages.empty, "Hələ söhbət yoxdur")
    }

    func testEngineChangesRedraw() async throws {
        await source.set(fresh: Fixture.aparConfig)
        let home = controller()
        await home.load()
        XCTAssertFalse(home.home.tabs.messagesUnread)
        let before = renders
        await source.push(unread: 1, .typing(conversationId: "conv_1", sender: Sender(type: .operator), isTyping: true))
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(renders, before, "typing is the conversation screen's business")
        await source.push(unread: 2, .unread(total: 2))
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(home.home.tabs.messagesUnread)
        XCTAssertEqual(renders, before + 1)
    }

    func testStartingAConversation() async {
        await source.set(fresh: Fixture.aparConfig)
        let home = controller()
        await home.load()
        async let first = home.startConversation(openedFrom: "home")
        async let second = home.startConversation(openedFrom: "home")
        let ids = await [first, second]
        XCTAssertEqual(ids.compactMap { $0 }, ["conv_1"], "a second tap while the first is starting does nothing")
        let starts = await source.starts
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(home.messages.rows.first?.id, "conv_1")

        await source.set(cached: Fixture.aparConfig, startFails: true)
        let failed = await home.startConversation(openedFrom: nil)
        XCTAssertNil(failed)
    }

    func testNameAndConnectivityRedraw() {
        let home = controller(user: nil)
        XCTAssertEqual(home.home.header.greeting, "Salam 👋")
        home.userName = "Leyla Əliyeva"
        XCTAssertEqual(home.home.header.greeting, "Salam, Leyla 👋")
        home.isOffline = true
        XCTAssertEqual(home.home.offline, "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq")
        XCTAssertEqual(renders, 2)
    }

    func testTheEngineIsADataSource() {
        let engine: MessengerDataSource = ClomniEngine(appId: "app_test", apiKey: "ios_sdk-test")
        XCTAssertNotNil(engine)
    }
}
