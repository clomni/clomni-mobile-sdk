import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

/// Reads protocol/fixtures from the repository, like the protocol tests.
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures")

    static func data(_ name: String) -> Data {
        (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data()
    }

    /// Config v2, from ios/Tests/Fixtures until protocol/fixtures has it.
    static let configDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static var aparConfig: MessengerConfig { config("config-v2-apar.json") }
    static var minimalConfig: MessengerConfig { config("config-v2-minimal.json") }

    static func config(_ name: String) -> MessengerConfig {
        ProtocolJSON.parseConfig((try? Data(contentsOf: configDirectory.appendingPathComponent(name))) ?? Data())!
    }

    /// A conversation whose last message is the fixture `message` (created at 2026-10-01T10:30Z, or `at`).
    static func conversation(_ id: String, message: String?, unread: Int = 0, assignee: String? = nil,
                             at: String = "2026-10-01T10:30:00Z") -> Conversation {
        var last = "null"
        if let message {
            last = String(decoding: data(message), as: UTF8.self)
                .replacingOccurrences(of: #""created_at": "[^"]*""#, with: #""created_at": "\#(at)""#, options: .regularExpression)
        }
        let person = assignee.map { #"{"name":"\#($0)","avatar_url":"https://app.clomni.ai/a/\#($0.lowercased()).png"}"# } ?? "null"
        let json = #"{"id":"\#(id)","status":"open","assignee":\#(person),"unread_count":\#(unread),"last_message":\#(last),"created_at":"2026-09-30T08:00:00Z"}"#
        return ProtocolJSON.parseConversation(Data(json.utf8))!
    }
}

final class PresenterTests: XCTestCase {
    /// 2026-10-01T10:32Z: two minutes after the fixtures' messages.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!

    private func presenter(_ language: String = "az", config: MessengerConfig? = Fixture.aparConfig) -> HomePresenter {
        HomePresenter(strings: ClomniStrings(language: language, overrides: config?.strings ?? [:]), timeZone: utc, now: now)
    }

    private func snapshot(_ config: MessengerConfig? = Fixture.aparConfig, _ conversations: [Conversation] = [],
                          user: String? = "Aysel Məmmədova") -> MessengerSnapshot {
        var snapshot = MessengerSnapshot(config: config, conversations: conversations, userName: user)
        snapshot.configLoad = .loaded
        snapshot.conversationsLoad = .loaded
        return snapshot
    }

    func testHeader() {
        let header = presenter().home(snapshot()).header
        XCTAssertEqual(header.brandName, "Apar")
        XCTAssertEqual(header.brandInitial, "A")
        XCTAssertEqual(header.logoUrl?.absoluteString, "https://app.clomni.ai/v1/images/apar-logo")
        XCTAssertEqual(header.logoDarkUrl?.absoluteString, "https://app.clomni.ai/v1/images/apar-logo-dark")
        XCTAssertEqual(header.style, .gradient)
        XCTAssertFalse(header.glow)
        XCTAssertEqual(header.teamAvatars.count, 3)
        // {name} is the whole name (APPEARANCE-CONTRACT § 1).
        XCTAssertEqual(header.greeting, "Salam, Aysel Məmmədova 👋")
        XCTAssertEqual(header.title, "Necə kömək edə bilərik?")
        XCTAssertEqual(header.closeLabel, "Bağla")

        XCTAssertEqual(presenter().home(snapshot(user: nil)).header.greeting, "Salam 👋")
        XCTAssertEqual(presenter().home(snapshot(user: "   ")).header.greeting, "Salam 👋")
        XCTAssertEqual(presenter("en").home(snapshot(user: "Aysel")).header.greeting, "Hi, Aysel 👋")
        XCTAssertEqual(presenter("ru").home(snapshot(user: nil)).header.greeting, "Здравствуйте 👋")

        let minimal = presenter(config: Fixture.minimalConfig).home(snapshot(Fixture.minimalConfig)).header
        XCTAssertEqual(minimal.title, "Necə kömək edə bilərik?", "the SDK's text when the config has none")
        XCTAssertNil(minimal.logoUrl)
        XCTAssertEqual(minimal.brandInitial, "C")
    }

    func testCardsFollowTheConfig() {
        let operatorReply = Fixture.conversation("conv_1", message: "02-text-operator-markdown.json", unread: 1)
        let apar = presenter().home(snapshot(Fixture.aparConfig, [operatorReply]))
        XCTAssertEqual(apar.phase, .ready)
        XCTAssertEqual(apar.newConversation?.title, "Bizə mesaj göndərin")
        XCTAssertEqual(apar.newConversation?.subtitle, "Adətən bir neçə dəqiqəyə cavab veririk")
        XCTAssertEqual(apar.newConversation?.accessibilityLabel,
                       "Bizə mesaj göndərin. Adətən bir neçə dəqiqəyə cavab veririk")
        XCTAssertEqual(apar.recent?.label, "Son mesaj")
        XCTAssertEqual(apar.channels?.label, "Bizi izləyin")
        XCTAssertEqual(apar.channels?.items.map(\.accessibilityLabel), ["Instagram", "WhatsApp", "LinkedIn", "E-poçt"])
        XCTAssertNil(apar.offline)
        XCTAssertNil(apar.failure)

        // Minimal config: only "new conversation"; no channels, so no "Bizi izləyin"; no reply time.
        let minimal = presenter(config: Fixture.minimalConfig).home(snapshot(Fixture.minimalConfig, [operatorReply]))
        XCTAssertNotNil(minimal.newConversation)
        XCTAssertNil(minimal.newConversation?.subtitle)
        XCTAssertNil(minimal.recent, "the config does not list recent_conversation")
        XCTAssertNil(minimal.channels)
        XCTAssertTrue(minimal.header.teamAvatars.isEmpty)
    }

    /// More channels than fit a row continue on the next one instead of running past the card.
    func testChannelRows() throws {
        let types = ["instagram", "whatsapp", "telegram", "facebook", "messenger", "linkedin", "youtube", "tiktok", "x"]
        let channels = types.map { #"{"type":"\#($0)","url":"https://\#($0).com/apar"}"# }.joined(separator: ",")
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Apar","primary_color":"#1F9D63"},"home":{"channels":[\##(channels)]}}
            """##.utf8)))
        let card = try XCTUnwrap(presenter(config: config).home(snapshot(config)).channels)
        XCTAssertEqual(card.items.map(\.url.host), ["instagram.com", "whatsapp.com", "telegram.com", "facebook.com", "messenger.com"],
                       "at most five, in the panel's order")
        XCTAssertEqual(card.rows().map(\.count), [5])
        XCTAssertEqual(card.rows(of: 4).map(\.count), [4, 1])
        XCTAssertEqual(card.rows().flatMap { $0 }, card.items, "in their order")
        XCTAssertEqual(card.rows(of: 0).count, 5, "never zero per row")
        XCTAssertEqual(HomeScreen.ChannelsCard(label: "x", items: []).rows(), [])
    }

    /// Config v2: what the panel publishes reaches Home (APPEARANCE-CONTRACT § 1, § 4).
    func testAppearanceFromThePanel() throws {
        let apar = presenter().home(snapshot(Fixture.aparConfig, [Fixture.conversation("conv_1", message: "02-text-operator-markdown.json")]))
        XCTAssertEqual(apar.order, [.send, .recent, .channels])
        XCTAssertEqual(apar.poweredBy, "Powered by Clomni")

        let json = ##"""
            {"brand":{"name":"Apar","primary_color":"#1F9D63","logo_url":"https://app.clomni.ai/v1/images/logo",
                      "header_style":"image","header_image_url":"https://app.clomni.ai/v1/images/head","glow":true},
             "team":{"show":false,"avatars":["https://app.clomni.ai/a/leyla.png"],"reply_time":"Tez",
                     "reply_time_offline":"Səhər cavab veririk","office_hours":{"open_now":false}},
             "bot":{"name":"Clomni","avatar_url":null},
             "home":{"cards":["channels","recent","send"],"channels":[{"type":"instagram","url":"https://instagram.com/apar.az"}]},
             "strings":{"greeting_line1":"Xoş gəldin, {first_name}!","greeting_line2":"Sualınız var?",
                        "send_card_title":"Yazın"},
             "powered_by":false}
            """##
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(Data(json.utf8)))
        let home = presenter(config: config).home(snapshot(config, [Fixture.conversation("conv_1", message: "02-text-operator-markdown.json")]))
        XCTAssertEqual(home.order, [.channels, .recent, .send], "the panel's order")
        XCTAssertNil(home.poweredBy, "the plan turned it off")
        XCTAssertEqual(home.header.style, .image(URL(string: "https://app.clomni.ai/v1/images/head")!))
        XCTAssertTrue(home.header.glow)
        XCTAssertEqual(home.header.teamAvatars, [], "team.show false")
        XCTAssertEqual(home.header.greeting, "Xoş gəldin, Aysel!")
        XCTAssertEqual(home.header.title, "Sualınız var?")
        XCTAssertEqual(home.newConversation?.title, "Yazın")
        XCTAssertEqual(home.newConversation?.subtitle, "Səhər cavab veririk", "the office is closed")
        XCTAssertEqual(config.botAvatarUrl?.absoluteString, "https://app.clomni.ai/v1/images/logo",
                       "no bot picture: the brand's logo")

        // Without a recent conversation or channels, those cards are not in the order at all.
        let bare = presenter(config: config).home(snapshot(config))
        XCTAssertEqual(presenter(config: config).home(snapshot(config, [])).order, [.channels, .send])
        XCTAssertNil(bare.recent)
        // An image style without its picture is the gradient.
        let noPicture = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"brand":{"header_style":"image"}}"#.utf8)))
        XCTAssertEqual(presenter(config: noPicture).home(snapshot(noPicture)).header.style, .gradient)
        let solid = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"brand":{"header_style":"solid"}}"#.utf8)))
        XCTAssertEqual(presenter(config: solid).home(snapshot(solid)).header.style, .solid)
    }

    func testRecentMessageIsHiddenWithoutAConversation() {
        XCTAssertNil(presenter().home(snapshot(Fixture.aparConfig, [])).recent)
        let empty = Fixture.conversation("conv_new", message: nil)
        XCTAssertNil(presenter().home(snapshot(Fixture.aparConfig, [empty])).recent, "nothing written in it yet")
    }

    func testRecentMessageRow() throws {
        let fromOperator = Fixture.conversation("conv_1", message: "02-text-operator-markdown.json", unread: 2)
        let row = try XCTUnwrap(presenter().home(snapshot(Fixture.aparConfig, [fromOperator])).recent?.row)
        XCTAssertEqual(row.id, "conv_1")
        XCTAssertEqual(row.preview, "Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər")
        XCTAssertEqual(row.detail, "Leyla · 2 dəq")
        XCTAssertEqual(row.initial, "L")
        XCTAssertEqual(row.avatarUrl?.absoluteString, "https://app.clomni.ai/a/leyla.png")
        XCTAssertTrue(row.unread)
        XCTAssertEqual(row.accessibilityLabel,
                       "Leyla, 2 dəq: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı. Ətraflı: şərtlər. Oxunmamış")

        // The user wrote last: "Siz", and the other side's face.
        let fromUser = Fixture.conversation("conv_2", message: "03-text-user.json", assignee: "Rauf",
                                            at: "2026-10-01T10:31:50Z")
        let mine = try XCTUnwrap(presenter().row(fromUser, config: Fixture.aparConfig))
        XCTAssertEqual(mine.detail, "Siz · indi")
        XCTAssertEqual(mine.initial, "R")
        XCTAssertEqual(mine.avatarUrl?.absoluteString, "https://app.clomni.ai/a/rauf.png")
        XCTAssertFalse(mine.unread)
        XCTAssertFalse(mine.accessibilityLabel.contains("Oxunmamış"))

        // A bot's quick replies: its fallback text on one line, the bot's name and avatar.
        let fromBot = Fixture.conversation("conv_3", message: "10-apar-level2-S-chips.json")
        let bot = try XCTUnwrap(presenter().row(fromBot, config: Fixture.aparConfig))
        XCTAssertEqual(bot.preview,
                       "Probleminiz nə ilə bağlıdır? Parking zona / Velosiped dayandı / Texniki nasazlıq / Kilidləmə / Əşyamı itirdim")
        XCTAssertEqual(bot.detail, "Clomni · 2 dəq")
        XCTAssertEqual(bot.avatarUrl?.absoluteString, "https://app.clomni.ai/a/bot.png")

        // A system message: the brand speaks.
        let system = try XCTUnwrap(presenter(config: Fixture.minimalConfig)
            .row(Fixture.conversation("conv_4", message: "23-system-operator-joined.json"), config: Fixture.minimalConfig))
        XCTAssertEqual(system.detail, "Clomni, Inc. · 2 dəq")
        XCTAssertEqual(system.preview, "Leyla söhbətə qoşuldu")
    }

    func testMarkdownIsRemovedFromPreviews() {
        func preview(_ text: String) -> String {
            let message = Message(id: "msg_1", conversationId: "conv_1", type: "text", sender: Sender(type: .bot),
                                  createdAt: now, seq: 1, lang: "az", content: .text(text), fallbackText: text)
            return HomePresenter.plainText(message)
        }
        XCTAssertEqual(preview("**Salam!** *Xoş* gəldiniz\n\n[şərtlər](https://apar.az) 2*3"), "Salam! Xoş gəldiniz şərtlər 2*3")
        XCTAssertEqual(preview("👍🙏"), "👍🙏")
    }

    func testTabDot() {
        var quiet = snapshot(Fixture.aparConfig, [Fixture.conversation("conv_1", message: "02-text-operator-markdown.json")])
        XCTAssertFalse(presenter().home(quiet).tabs.messagesUnread)
        XCTAssertEqual(presenter().home(quiet).tabs.messagesAccessibilityLabel, "Mesajlar")
        quiet.unreadTotal = 1
        let tabs = presenter().home(quiet).tabs
        XCTAssertTrue(tabs.messagesUnread)
        XCTAssertEqual(tabs.home, "Ana səhifə")
        XCTAssertEqual(tabs.messagesAccessibilityLabel, "Mesajlar, Oxunmamış mesaj var")
        let unreadInList = snapshot(Fixture.aparConfig,
                                    [Fixture.conversation("conv_1", message: "02-text-operator-markdown.json", unread: 1)])
        XCTAssertTrue(presenter().home(unreadInList).tabs.messagesUnread, "before the first unread.changed")
    }

    func testLoadingFailureAndOffline() {
        var nothing = MessengerSnapshot()
        XCTAssertEqual(presenter(config: nil).home(nothing).phase, .loading)
        XCTAssertEqual(presenter(config: nil).messages(nothing).phase, .loading)
        // The open messenger while the SDK gets ready, and when that failed.
        XCTAssertEqual(presenter(config: nil).preparing(failed: false).phase, .loading)
        let notReached = presenter(config: nil).preparing(failed: true)
        XCTAssertEqual(notReached.phase, .failed)
        XCTAssertEqual(notReached.failure, HomeScreen.Failure(message: "Nəsə səhv getdi", retry: "Yenidən cəhd et"))
        // VoiceOver hears this over the skeleton blocks.
        XCTAssertEqual(presenter(config: nil).home(nothing).loadingLabel, "Yüklənir")
        XCTAssertEqual(presenter("en", config: nil).messages(nothing).loadingLabel, "Loading")
        nothing.configLoad = .failed
        nothing.conversationsLoad = .failed
        let failed = presenter(config: nil).home(nothing)
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.failure, HomeScreen.Failure(message: "Nəsə səhv getdi", retry: "Yenidən cəhd et"))
        XCTAssertEqual(presenter(config: nil).messages(nothing).phase, .failed)

        // A cached config is shown even when the refresh failed.
        var cached = snapshot()
        cached.configLoad = .failed
        cached.isOffline = true
        let home = presenter().home(cached)
        XCTAssertEqual(home.phase, .ready)
        XCTAssertNil(home.failure)
        XCTAssertEqual(home.offline, "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq")
        XCTAssertEqual(presenter().messages(cached).offline, home.offline)
    }

    func testMessagesTab() {
        let list = [Fixture.conversation("conv_2", message: "03-text-user.json"),
                    Fixture.conversation("conv_new", message: nil),
                    Fixture.conversation("conv_1", message: "02-text-operator-markdown.json")]
        let messages = presenter().messages(snapshot(Fixture.aparConfig, list))
        XCTAssertEqual(messages.title, "Mesajlar")
        XCTAssertEqual(messages.phase, .ready)
        XCTAssertEqual(messages.rows.map(\.id), ["conv_2", "conv_1"])
        XCTAssertNil(messages.empty)
        XCTAssertEqual(messages.newConversation.title, "Bizə mesaj göndərin")

        let empty = presenter().messages(snapshot(Fixture.aparConfig, []))
        XCTAssertEqual(empty.empty, "Hələ söhbət yoxdur")
        XCTAssertEqual(empty.phase, .ready)
        XCTAssertNil(empty.failure)

        var stale = snapshot(Fixture.aparConfig, list)
        stale.conversationsLoad = .failed
        XCTAssertEqual(presenter().messages(stale).phase, .ready, "the cached list stays")
        XCTAssertEqual(presenter("ru").messages(snapshot(Fixture.aparConfig, [])).empty, "Пока нет переписки")
    }
}
