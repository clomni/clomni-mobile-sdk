import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore
@testable import ClomniPresentation

/// SDK 1.0.7 on screen: deleting the user's own message, the deleted bubble, the operator's quote, the tab bar, the news
/// on Home and the FAQ.
final class DeletingPresenterTests: XCTestCase {
    /// 2026-10-01T10:32:00Z.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!

    private func bubbles(_ messages: [Message], status: String = "open",
                         _ build: (inout ChatSnapshot) -> Void = { _ in }) -> [Bubble] {
        var snapshot = ChatSnapshot(config: Fixture.exampleConfig, conversation: Fixture.conversation(status: status),
                                    messages: messages)
        snapshot.load = .loaded
        build(&snapshot)
        let screen = ChatPresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now).screen(snapshot)
        return screen.items.compactMap { if case .bubble(let bubble) = $0 { return bubble }; return nil }
    }

    func testOnlyTheUsersOwnMessageCanBeDeletedWhileTheConversationIsNotClosed() {
        let mine = Fixture.message("03-text-user.json")
        let leylas = Fixture.message("02-text-operator-markdown.json")
        for status in ["bot", "queued", "open"] {
            XCTAssertEqual(bubbles([leylas, mine], status: status).map(\.deleteId), [nil, "msg_f03"], status)
        }
        XCTAssertEqual(bubbles([leylas, mine], status: "closed").map(\.deleteId), [nil, nil], "closed: none")
        // Not sent yet: by its client id, so the outbox gives it up.
        let pending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Gəlmədi")),
                                     preview: "Gəlmədi", createdAt: now)
        let sending = bubbles([mine]) { $0.pending = [pending] }
        XCTAssertEqual(sending.last?.deleteId, pending.id)
        XCTAssertNil(bubbles([mine], status: "closed") { $0.pending = [pending] }.last?.deleteId)

        let screen = ChatPresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now)
            .screen(ChatSnapshot(config: Fixture.exampleConfig))
        XCTAssertEqual(screen.deleting, DeleteTexts(ClomniStrings(language: "az")))
        XCTAssertEqual([screen.deleting.action, screen.deleting.title, screen.deleting.body, screen.deleting.cancel],
                       ["Sil", "Mesaj silinsin?", "Mesaj hər kəs üçün silinəcək.", "Ləğv et"])
    }

    /// Fixture 107: on its side, "Bu mesaj silindi", its time and no ticks; nothing to answer, copy or delete.
    func testADeletedMessageIsAMutedBubbleWithNothingToDo() {
        let deleted = Fixture.message("107-deleted-user-message.json")
        let bubble = bubbles([deleted]).first
        XCTAssertEqual(bubble?.side, .outgoing)
        XCTAssertEqual(bubble?.body, .deleted("Bu mesaj silindi"))
        XCTAssertEqual(bubble?.time, "09:12")
        XCTAssertNil(bubble?.status, "no ticks")
        XCTAssertNil(bubble?.quote)
        XCTAssertEqual(bubble?.replyable, false)
        XCTAssertNil(bubble?.copyText)
        XCTAssertNil(bubble?.deleteId)
        XCTAssertEqual(bubble?.accessibilityLabel, "Siz, 09:12: Bu mesaj silindi")
        // The operator's, deleted in the panel, comes as message.updated (fixture 108), in the user's language here.
        guard case .messageUpdated(let operators)? = ProtocolJSON.parseEvent(Fixture.data("108-event-message-deleted-by-operator.json"))?.data
        else { return XCTFail("fixture 108") }
        XCTAssertEqual(bubbles([operators]).first?.body, .deleted("Bu mesaj silindi"))
        XCTAssertEqual(bubbles([operators]).first?.side, .incoming)
    }

    /// A quote of a message deleted since reads "Mesaj silinib", over the bubble and over the field; a message being
    /// quoted in the composer that is deleted meanwhile is no longer quoted.
    func testAQuoteOfADeletedMessage() {
        let reply = Fixture.message("66-reply-user-to-operator.json")
        let quoted = Fixture.message("02-text-operator-markdown.json", ["id": "msg_f65", "seq": 13])
        XCTAssertEqual(bubbles([quoted, reply]).last?.quote?.excerpt,
                       "Ödənişi kartla etmisiniz, yoxsa balansdan? Qəbzin şəklini də göndərə bilərsiniz, yoxlayaq.")
        let gone = quoted.deleted()
        XCTAssertEqual(bubbles([gone, reply]).last?.quote, Bubble.Quote(messageId: "msg_f65", author: "Leyla",
                                                                       excerpt: "Mesaj silinib"))
        var snapshot = ChatSnapshot(config: Fixture.exampleConfig, conversation: Fixture.conversation(status: "open"),
                                    messages: [gone])
        snapshot.load = .loaded
        snapshot.replyingTo = gone.id
        XCTAssertNil(ChatPresenter(strings: ClomniStrings(language: "az"), now: now).screen(snapshot).composer.quote)
    }

    /// CM-342 item 3: an operator's reply (`reply_to` from the panel) shows its quote over the operator's bubble too.
    func testTheOperatorsReplyShowsItsQuote() {
        let reply = Fixture.message("67-reply-operator-to-image.json")
        let bubble = bubbles([reply]).first
        XCTAssertEqual(bubble?.side, .incoming)
        XCTAssertEqual(bubble?.quote, Bubble.Quote(messageId: "msg_f62", author: "Siz", excerpt: "qebz.jpg"))
    }

    /// Home's last message, deleted: "Bu mesaj silindi", not what it said.
    func testADeletedLastMessageOnHome() throws {
        let conversation = Fixture.conversation("conv_1", message: "107-deleted-user-message.json")
        let row = try XCTUnwrap(HomePresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now)
            .row(conversation, config: Fixture.exampleConfig))
        XCTAssertEqual(row.preview, "Bu mesaj silindi")
    }
}

@MainActor
final class DeletingControllerTests: XCTestCase {
    private let source = FakeChat()

    private func controller() -> ChatController {
        ChatController(source: source, conversationId: "conv_5521", language: "az",
                       timeZone: TimeZone(identifier: "UTC")!, now: { Date(timeIntervalSince1970: 1_790_850_720) })
    }

    func testDeletingShowsTheDeletedBubbleAndDropsItsQuote() async {
        let mine = Fixture.message("03-text-user.json")
        await source.set([mine])
        let chat = controller()
        await chat.load()
        chat.reply(to: mine.id)
        XCTAssertNotNil(chat.screen.composer.quote)
        let refusal = await chat.delete(mine.id)
        XCTAssertNil(refusal)
        await chat.settled()
        await source.push(.messages(conversationId: "conv_5521"))
        await chat.settled()
        XCTAssertNil(chat.screen.composer.quote, "what is deleted is not quoted")
        guard case .bubble(let bubble)? = chat.screen.items.last else { return XCTFail("\(chat.screen.items)") }
        XCTAssertEqual(bubble.body, .deleted("Bu mesaj silindi"))
        let calls = await source.calls
        XCTAssertTrue(calls.contains("delete msg_f03"), "\(calls)")
    }

    /// 409: "Söhbət bağlanıb, mesaj silinmir.", the message stays, and the conversation is asked for again (closed: no
    /// composer). Any other failure: "Nəsə səhv getdi".
    func testAClosedConversationOrNoAnswerKeepsTheMessage() async {
        let mine = Fixture.message("03-text-user.json")
        await source.set([mine])
        await source.setConversation(Fixture.conversation(status: "closed"))
        await source.setDeleteAnswer(.closed)
        let chat = controller()
        await chat.load()
        let refusal = await chat.delete(mine.id)
        XCTAssertEqual(refusal, "Söhbət bağlanıb, mesaj silinmir.")
        let calls = await source.calls
        XCTAssertEqual(calls.filter { $0.hasPrefix("refreshConversation") }.count, 2, "at the opening and after the 409")
        guard case .bubble(let bubble)? = chat.screen.items.last else { return XCTFail("\(chat.screen.items)") }
        XCTAssertEqual(bubble.messageId, mine.id)
        XCTAssertNil(bubble.deleteId, "closed now: no more Sil")

        await source.setDeleteAnswer(.failed)
        let failed = await chat.delete(mine.id)
        XCTAssertEqual(failed, "Nəsə səhv getdi")
    }
}

final class TabsNewsFaqPresenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!
    private var tabbed: MessengerConfig { ProtocolJSON.parseConfig(Fixture.data("109-config-tab-bar-faq.json"))! }
    private var news: [NewsItem] { ProtocolJSON.parseNews(Fixture.data("61-news.json"))! }
    private var faq: [FaqItem] { ProtocolJSON.parseFaq(Fixture.data("110-faq.json"))! }

    private func presenter(_ config: MessengerConfig?) -> HomePresenter {
        HomePresenter(strings: ClomniStrings(language: "az", overrides: config?.strings ?? [:]), timeZone: utc, now: now)
    }

    private func snapshot(_ config: MessengerConfig?, news: [NewsItem] = [], faq: [FaqItem] = [],
                          unread: Int = 0) -> MessengerSnapshot {
        var snapshot = MessengerSnapshot(config: config)
        snapshot.configLoad = .loaded
        snapshot.conversationsLoad = .loaded
        snapshot.news = news
        snapshot.faq = faq
        snapshot.unreadTotal = unread
        return snapshot
    }

    /// Home, the conversations with the unread count, then the news and the FAQ while there are some.
    func testTheTabsAreThereWhileTheyHaveSomethingToShow() throws {
        let all = try XCTUnwrap(presenter(tabbed).tabBar(snapshot(tabbed, news: news, faq: faq, unread: 3)))
        XCTAssertEqual(all.items.map(\.tab), [.home, .messages, .news, .faq])
        XCTAssertEqual(all.items.map(\.title), ["Əsas səhifə", "Söhbətlər", "Xəbərlər", "Suallar"])
        XCTAssertEqual(all.items.map(\.badge), [nil, "3", nil, nil])
        XCTAssertEqual(all.items[1].accessibilityLabel, "Söhbətlər, 3 oxunmamış")
        XCTAssertEqual(presenter(tabbed).tabBar(snapshot(tabbed, news: news, faq: faq, unread: 120))?.items[1].badge, "99+")

        XCTAssertEqual(presenter(tabbed).tabBar(snapshot(tabbed))?.items.map(\.tab), [.home, .messages],
                       "no news, no questions")
        XCTAssertEqual(presenter(tabbed).tabBar(snapshot(tabbed, faq: faq))?.items.map(\.tab), [.home, .messages, .faq])
        XCTAssertNil(presenter(tabbed).tabBar(snapshot(tabbed))?.items[1].badge, "nothing unread")

        // The FAQ off in the panel: no tab, whatever is cached.
        let faqOff = ProtocolJSON.parseConfig(Data(String(decoding: Fixture.data("109-config-tab-bar-faq.json"), as: UTF8.self)
            .replacingOccurrences(of: #""enabled": true"#, with: #""enabled": false"#).utf8))!
        XCTAssertFalse(faqOff.faqEnabled)
        XCTAssertEqual(presenter(faqOff).tabBar(snapshot(faqOff, news: news, faq: faq))?.items.map(\.tab),
                       [.home, .messages, .news])

        // tab_bar false or absent: none anywhere, as before 1.0.7.
        let example = Fixture.exampleConfig
        let plain = snapshot(example, news: news, faq: faq)
        XCTAssertNil(presenter(example).tabBar(plain))
        XCTAssertNil(presenter(example).home(plain).tabBar)
        XCTAssertNil(presenter(example).messages(plain).tabBar)
        XCTAssertNil(presenter(example).newsList(plain).tabBar)
        XCTAssertNil(presenter(example).faq(plain).tabBar)
        let tabbedSnapshot = snapshot(tabbed, news: news, faq: faq)
        XCTAssertNotNil(presenter(tabbed).home(tabbedSnapshot).tabBar)
        XCTAssertNotNil(presenter(tabbed).messages(tabbedSnapshot).tabBar)
        XCTAssertNotNil(presenter(tabbed).newsList(tabbedSnapshot).tabBar)
        XCTAssertNotNil(presenter(tabbed).faq(tabbedSnapshot).tabBar)
    }

    /// news_on_home: that many on Home, "Hamısı" only while there are more; every one in the news list.
    func testNewsOnHome() throws {
        let one = presenter(tabbed).home(snapshot(tabbed, news: news))
        XCTAssertEqual(one.news?.items.map(\.id), ["news_12"], "fixture 109: one")
        XCTAssertEqual(one.news?.seeAll, "Hamısı", "two news, one on the card")
        let two = presenter(Fixture.exampleConfig).home(snapshot(Fixture.exampleConfig, news: news))
        XCTAssertEqual(two.news?.items.map(\.id), ["news_12", "news_9"], "absent: two")
        XCTAssertNil(two.news?.seeAll, "as many as the card holds: no link")
        let fewer = presenter(Fixture.exampleConfig).home(snapshot(Fixture.exampleConfig, news: Array(news.prefix(1))))
        XCTAssertEqual(fewer.news?.items.count, 1)
        XCTAssertNil(fewer.news?.seeAll, "fewer than the card holds: no link")
        XCTAssertNil(presenter(tabbed).home(snapshot(tabbed)).news, "no news, no card")

        let list = presenter(tabbed).newsList(snapshot(tabbed, news: news))
        XCTAssertEqual(list.title, "Xəbərlər")
        XCTAssertEqual(list.items.map(\.id), ["news_12", "news_9"])
    }

    /// The FAQ card: the first three questions, "Hamısı" while there are more, where the panel put it, only while
    /// the FAQ is on and has a question.
    func testTheFaqCard() throws {
        let home = presenter(tabbed).home(snapshot(tabbed, faq: faq))
        let card = try XCTUnwrap(home.faq)
        XCTAssertEqual(card.title, "Tez-tez verilən suallar")
        XCTAssertEqual(card.items.map(\.id), ["faq_12", "faq_9", "faq_15"])
        XCTAssertEqual(card.seeAll, "Hamısı", "four questions")
        XCTAssertNil(presenter(tabbed).home(snapshot(tabbed, faq: Array(faq.prefix(3)))).faq?.seeAll, "three: no link")
        XCTAssertTrue(home.order.contains(.faq))
        XCTAssertNil(presenter(tabbed).home(snapshot(tabbed)).faq, "no questions")
        XCTAssertFalse(presenter(tabbed).home(snapshot(tabbed)).order.contains(.faq))
        XCTAssertNil(presenter(Fixture.exampleConfig).home(snapshot(Fixture.exampleConfig, faq: faq)).faq,
                     "FAQ off and not in the cards")
    }

    /// The list: the questions in the panel's order, a search over questions and answers on the device that ignores
    /// case and Azerbaijani letters; an answer on the news item's screen.
    func testTheFaqListAndItsSearch() throws {
        let screen = presenter(tabbed).faq(snapshot(tabbed, faq: faq))
        XCTAssertEqual([screen.title, screen.searchPlaceholder, screen.empty, screen.noResults],
                       ["Tez-tez verilən suallar", "Sual axtarın", "Hələ sual yoxdur", "Heç nə tapılmadı"])
        XCTAssertEqual(screen.entries.map(\.id), ["faq_12", "faq_9", "faq_15", "faq_16"])
        let answer = NewsArticle(faq[0], strings: ClomniStrings(language: "az"))
        XCTAssertEqual(answer.title, "Gedişin pulunu necə qaytara bilərəm?")
        XCTAssertEqual(answer.date, "")
        XCTAssertNil(answer.imageUrl)
        XCTAssertNil(answer.button)
        XCTAssertEqual(answer.blocks.first,
                       .paragraph([TextRun("Gediş bitəndən sonra "), TextRun("24 saat", bold: true), TextRun(" ərzində müraciət edin.")]))
        XCTAssertEqual(answer.blocks.filter { if case .listItem = $0 { return true }; return false }.count, 2)

        XCTAssertEqual(screen.matching("").map(\.id), ["faq_12", "faq_9", "faq_15", "faq_16"])
        XCTAssertEqual(screen.matching("kart").map(\.id), ["faq_9"], "in the question")
        XCTAssertEqual(screen.matching("PROMOKOD").map(\.id), ["faq_16"], "any case")
        XCTAssertEqual(screen.matching("24 saat").map(\.id), ["faq_12"], "in the answer, without its marks")
        XCTAssertEqual(screen.matching("gedisin").map(\.id), ["faq_12"], "ş read as s, ı as i")
        XCTAssertEqual(screen.matching("deyisim").map(\.id), ["faq_9"], "ə read as e")
        XCTAssertEqual(screen.matching("kart  dəyiş").map(\.id), ["faq_9"], "every word")
        XCTAssertEqual(screen.matching("velosiped"), [])

        XCTAssertEqual(presenter(tabbed).faq(snapshot(tabbed)).entries, [], "no questions: faq_empty shows")
    }
}

@MainActor
final class TabsCoordinatorTests: XCTestCase {
    private let session = FakeSession()

    private func open(tabBar: Bool) async -> MessengerCoordinator {
        let config = tabBar ? ProtocolJSON.parseConfig(Fixture.data("109-config-tab-bar-faq.json"))! : Fixture.exampleConfig
        await session.set(loggedIn: true, cached: config, fresh: config)
        let messenger = MessengerCoordinator(session: session, language: "az")
        await messenger.start()
        messenger.present()
        return messenger
    }

    /// With the tab bar every list is a tab: alone at the bottom, nothing to go back to; a conversation goes over it
    /// and back returns to the tab. The same tab again changes nothing.
    func testWithTheTabBarAListIsATab() async {
        let messenger = await open(tabBar: true)
        XCTAssertEqual(messenger.stack, [.home])
        messenger.show(.messages)
        XCTAssertEqual(messenger.stack, [.messages], "Home's Mesajlar card: the conversations' tab")
        messenger.navigate(to: .conversation("conv_1"))
        XCTAssertEqual(messenger.stack, [.messages, .conversation("conv_1")])
        messenger.back()
        XCTAssertEqual(messenger.stack, [.messages])
        messenger.back()
        XCTAssertEqual(messenger.stack, [.messages], "a tab has nothing under it")
        messenger.select(.news)
        XCTAssertEqual(messenger.stack, [.newsList])
        messenger.navigate(to: .news("news_12"))
        XCTAssertEqual(messenger.stack, [.newsList, .news("news_12")])
        messenger.select(.faq)
        XCTAssertEqual(messenger.stack, [.faq])
        messenger.navigate(to: .faqAnswer("faq_9"))
        XCTAssertEqual(messenger.stack, [.faq, .faqAnswer("faq_9")], "an answer over the questions, no tab bar")
        XCTAssertNil(messenger.route?.tab)
        messenger.select(.home)
        messenger.show(.faqAnswer("faq_12"))
        XCTAssertEqual(messenger.stack, [.home, .faqAnswer("faq_12")], "a question on Home's card: its answer")
        messenger.select(.home)
        XCTAssertEqual(messenger.stack, [.home])
        XCTAssertEqual(messenger.route?.tab, .home)
        XCTAssertNil(MessengerRoute.conversation("conv_1").tab, "a conversation is no tab: no tab bar")
    }

    /// Without it, as before: pushed over Home, back to Home.
    func testWithoutTheTabBarAListIsPushedOverHome() async {
        let messenger = await open(tabBar: false)
        messenger.show(.messages)
        XCTAssertEqual(messenger.stack, [.home, .messages])
        messenger.back()
        messenger.show(.newsList)
        XCTAssertEqual(messenger.stack, [.home, .newsList], "Hamısı under the news card")
        messenger.back()
        messenger.show(.faq)
        XCTAssertEqual(messenger.stack, [.home, .faq])
        messenger.dismiss()
        messenger.select(.messages)
        XCTAssertEqual(messenger.stack, [], "nothing while closed")
    }
}

@MainActor
final class FaqHomeControllerTests: XCTestCase {
    private let source = FakeSource()

    /// GET /faq only while the panel shares it; the questions reach Home's card, the list and the tab bar; opening one
    /// is reported.
    func testTheFaqIsAskedForOnlyWhileItIsOn() async {
        let tabbed = ProtocolJSON.parseConfig(Fixture.data("109-config-tab-bar-faq.json"))!
        await source.set(cached: Fixture.exampleConfig, fresh: Fixture.exampleConfig)
        let off = HomeController(source: source, language: "az", userName: nil)
        await off.load()
        let notAsked = await source.faqRefreshes
        XCTAssertEqual(notAsked, 0)

        await source.set(cached: tabbed, fresh: tabbed)
        await source.set(faq: ProtocolJSON.parseFaq(Fixture.data("110-faq.json"))!)
        let on = HomeController(source: source, language: "az", userName: nil)
        await on.load()
        let asked = await source.faqRefreshes
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(on.home.faq?.items.count, 3)
        XCTAssertEqual(on.faq.entries.count, 4)
        XCTAssertEqual(on.faqAnswer("faq_9")?.title, "Kartı necə dəyişim?")
        XCTAssertNil(on.faqAnswer("faq_404"))
        XCTAssertEqual(on.home.tabBar?.items.map(\.tab), [.home, .messages, .faq])
        await on.faqOpened("faq_12")
        let opened = await source.opened
        XCTAssertEqual(opened, ["faq_12"])
    }
}
