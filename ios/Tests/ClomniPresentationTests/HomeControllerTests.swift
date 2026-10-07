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
    var starts = 0
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]
    var observerCount: Int { observers.count }

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

    func draftConversation(openedFrom: String?) async -> String {
        starts += 1
        return "draft_\(starts)"
    }

    var published: [NewsItem] = []
    var news: [NewsItem] { published }
    func refreshNews() async -> [NewsItem] { published }
    func set(news: [NewsItem]) { published = news }
    var opened: [String] = []
    func newsOpened(_ id: String) async { opened.append(id) }

    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func stopObserving(_ token: UUID) {
        observers[token] = nil
    }

    func set(cached: MessengerConfig? = nil, fresh: MessengerConfig? = nil, list: [Conversation]? = nil,
             conversationsFail: Bool = false) {
        self.cached = cached
        self.fresh = fresh
        if let list { self.list = list }
        self.conversationsFail = conversationsFail
    }

    var name: String?
    var userName: String? { name }

    /// The app's user logs in: the engine knows their name and says the session changed.
    func login(name: String) {
        self.name = name
        observers.values.forEach { $0(.session) }
    }

    /// What the engine does when a socket event arrives.
    func push(unread: Int, _ change: ClomniChange) {
        self.unread = unread
        observers.values.forEach { $0(change) }
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
        XCTAssertEqual(home.home.header.greeting, "Salam, Aysel")
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
        XCTAssertFalse(home.home.messagesCard.unread)
        let before = renders
        await source.push(unread: 1, .typing(conversationId: "conv_1", sender: Sender(type: .operator), isTyping: true))
        await home.settled()
        XCTAssertEqual(renders, before, "typing is the conversation screen's business")
        await source.push(unread: 2, .unread(total: 2))
        await home.settled()
        XCTAssertTrue(home.home.messagesCard.unread)
        XCTAssertEqual(renders, before + 1)

        await home.retry()
        let observers = await source.observerCount
        XCTAssertEqual(observers, 1, "loading again does not listen twice")
        await home.stop()
        let afterStop = await source.observerCount
        XCTAssertEqual(afterStop, 0)
    }

    func testStartingAConversation() async {
        await source.set(fresh: Fixture.aparConfig)
        let home = controller()
        await home.load()
        let id = await home.startConversation(openedFrom: "home")
        XCTAssertEqual(id, "draft_1", "a draft: nothing on the server until its first message")
        XCTAssertTrue(home.messages.rows.isEmpty, "not in the list either")
    }

    /// DESIGN-PASS-2 9: Home with a config is drawn with it from the first frame, and coming back to it (a load
    /// again) never passes through the SDK's default texts.
    func testHomeWithAConfigNeverShowsTheDefaults() async {
        await source.set(cached: nil, fresh: Fixture.aparConfig)
        let custom = Fixture.aparConfig.strings["greeting_line2"]
        XCTAssertEqual(custom, "Bizdən nəsə soruşun")
        let home = HomeController(source: source, language: nil, userName: "Aysel", config: Fixture.aparConfig)
        var titles = [home.home.header.title]
        XCTAssertEqual(home.home.phase, .ready, "the first frame")
        home.onChange = { titles.append(home.home.header.title) }
        await home.load()
        await home.load()
        XCTAssertEqual(Set(titles), ["Bizdən nəsə soruşun"], "\(titles)")
        XCTAssertNotEqual(home.home.header.title, ClomniStrings(language: "az")[.greetingLine2])
    }

    func testNewsReachHomeAndAnItemOpens() async throws {
        await source.set(fresh: Fixture.aparConfig)
        await source.set(news: try XCTUnwrap(ProtocolJSON.parseNews(Fixture.data("61-news.json"))))
        let home = controller()
        await home.load()
        XCTAssertEqual(home.home.news?.items.map(\.id), ["news_12", "news_9"])
        let article = try XCTUnwrap(home.article("news_12"))
        XCTAssertEqual(article.title, "Yeni zonalar açıldı")
        XCTAssertNil(home.article("news_404"))
        await home.opened(article)
        let opened = await source.opened
        XCTAssertEqual(opened, ["news_12"])
    }

    func testNameAndConnectivityRedraw() {
        let home = controller(user: nil)
        XCTAssertEqual(home.home.header.greeting, "Salam", "no emoji in the defaults")
        home.userName = "Leyla Əliyeva"
        XCTAssertEqual(home.home.header.greeting, "Salam, Leyla")
        home.isOffline = true
        XCTAssertEqual(home.home.offline, "İnternet yoxdur")
        XCTAssertEqual(renders, 2)
    }

    /// G6 (operator, 2026-10-07): `Clomni.loginUser(… name: "Aysel")` while Home is open; the greeting takes the
    /// name at once, from the engine. Nobody passes it in.
    func testTheGreetingTakesTheLoggedInUsersName() async {
        let home = controller(user: nil)
        await home.load()
        XCTAssertEqual(home.home.header.greeting, "Salam")
        await source.login(name: "Aysel Məmmədova")
        await home.settled()
        XCTAssertEqual(home.home.header.greeting, "Salam, Aysel")
    }

    func testTheEngineIsADataSource() {
        let engine: MessengerDataSource = ClomniEngine(appId: "app_test", apiKey: "ios_sdk-test")
        XCTAssertNotNil(engine)
    }
}
