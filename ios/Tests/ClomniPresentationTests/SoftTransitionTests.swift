import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

/// CM-346, TestFlight #19 and #21: the tabs' lists stay as they were; nothing cross-fades (§ 5.1): another tab
/// replaces the list at once, a screen opened over a list keeps the system's push, and every screen coming into view
/// shows its spinner first (`ScreenEntry`). Where there is nothing to show yet, the spinner, not a blank screen.
@MainActor
final class SoftTransitionTests: XCTestCase {
    private var tabbed: MessengerConfig { ProtocolJSON.parseConfig(Fixture.data("109-config-tab-bar-faq.json"))! }
    private var news: [NewsItem] { ProtocolJSON.parseNews(Fixture.data("61-news.json"))! }
    private var faq: [FaqItem] { ProtocolJSON.parseFaq(Fixture.data("110-faq.json"))! }

    func testHowTheStackMoves() {
        func move(_ shown: [MessengerRoute], _ next: [MessengerRoute]) -> StackTransition {
            StackTransition(from: shown, to: next, reduceMotion: false)
        }
        XCTAssertEqual(move([.home], [.messages]), .none, "another tab: at once, no cross-fade")
        XCTAssertEqual(move([.messages], [.faq]), .none)
        XCTAssertEqual(move([.newsList], [.home]), .none, "back to Home")
        XCTAssertEqual(move([.home], [.home, .conversation("conv_1")]), .push, "a conversation over the list")
        XCTAssertEqual(move([.messages, .conversation("conv_1")], [.messages]), .push, "and back")
        XCTAssertEqual(move([.home], [.home, .messages]), .push, "the list over Home, without the tab bar")
        XCTAssertEqual(move([.faq], [.faq, .faqAnswer("faq_12")]), .push)
        XCTAssertEqual(move([], [.home]), .none, "the opening: the sheet's own move")
        XCTAssertEqual(move([.messages, .conversation("conv_1")], [.home, .conversation("conv_2")]), .none,
                       "a whole new stack (a push's conversation)")
        XCTAssertEqual(StackTransition(from: [.home], to: [.home, .news("news_12")], reduceMotion: true), .none,
                       "Reduce Motion: at once")
    }

    /// The screens that show the spinner first: the new ones, a tab chosen again too; a pop shows what was under.
    func testWhichScreensComeIntoView() {
        XCTAssertEqual(StackTransition.entering(from: [], to: [.home]), 0..<1, "the opening")
        XCTAssertEqual(StackTransition.entering(from: [], to: [.home, .conversation("conv_1")]), 0..<2)
        XCTAssertEqual(StackTransition.entering(from: [.home], to: [.messages]), 0..<1, "another tab")
        XCTAssertEqual(StackTransition.entering(from: [.messages], to: [.home]), 0..<1, "Home again")
        XCTAssertEqual(StackTransition.entering(from: [.home], to: [.home, .news("news_12")]), 1..<2, "a push")
        XCTAssertTrue(StackTransition.entering(from: [.messages, .conversation("conv_1")], to: [.messages]).isEmpty,
                      "a pop: the list as it was")
    }

    func testOnlyTheTabsListsStayAlive() {
        for route in [MessengerRoute.home, .messages, .newsList, .faq] {
            XCTAssertTrue(route.keptAlive(atBottom: true), "\(route): a tab's list")
        }
        XCTAssertFalse(MessengerRoute.messages.keptAlive(atBottom: false), "pushed over Home: made each time")
        for route in [MessengerRoute.conversation("conv_1"), .news("news_12"), .faqAnswer("faq_12")] {
            XCTAssertFalse(route.keptAlive(atBottom: true), "\(route)")
        }
    }

    /// The news and the FAQ say they are still coming while nothing is cached; with something cached, or once the
    /// server has answered, they do not.
    func testTheListsSayWhileTheyAreLoading() {
        let presenter = HomePresenter(strings: ClomniStrings(language: "az"), now: Date())
        var snapshot = MessengerSnapshot(config: tabbed)
        XCTAssertTrue(presenter.newsList(snapshot).loading)
        XCTAssertTrue(presenter.faq(snapshot).loading)
        XCTAssertEqual(presenter.newsList(snapshot).loadingLabel, "Yüklənir")
        XCTAssertEqual(presenter.faq(snapshot).loadingLabel, "Yüklənir")

        snapshot.news = news
        snapshot.faq = faq
        XCTAssertFalse(presenter.newsList(snapshot).loading, "cached: at once")
        XCTAssertFalse(presenter.faq(snapshot).loading)

        snapshot.news = []
        snapshot.faq = []
        snapshot.listsLoad = .loaded
        XCTAssertFalse(presenter.newsList(snapshot).loading, "answered, and empty")
        XCTAssertFalse(presenter.faq(snapshot).loading)
    }

    func testTheListsAreLoadedOnceTheServerAnswered() async {
        let source = FakeSource()
        await source.set(cached: tabbed)
        let controller = HomeController(source: source, language: "az", userName: nil, config: tabbed)
        XCTAssertTrue(controller.newsList.loading)
        XCTAssertTrue(controller.faq.loading)
        await controller.load()
        XCTAssertFalse(controller.newsList.loading, "no news at all: not loading forever")
        XCTAssertFalse(controller.faq.loading)
    }
}
