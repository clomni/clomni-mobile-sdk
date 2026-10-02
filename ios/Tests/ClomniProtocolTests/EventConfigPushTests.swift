import Foundation
import XCTest
@testable import ClomniProtocol

final class RealtimeEventTests: ProtocolTestCase {
    func testReady() throws {
        let event = try Fixtures.event("33-event-ready.json")
        XCTAssertEqual(event.event, "ready")
        XCTAssertEqual(event.data, .ready(userId: "usr_12345", heartbeatSec: 25))
        XCTAssertEqual(event.ts, Date(timeIntervalSince1970: 1_790_850_601))
    }

    func testMessageCreatedAndUpdatedCarryTheMessage() throws {
        let created = try Fixtures.event("34-event-message-created.json")
        XCTAssertEqual(created.data, .messageCreated(try Fixtures.message("23-system-operator-joined.json")))

        guard case .messageUpdated(let updated) = try Fixtures.event("35-event-message-updated.json").data else {
            return XCTFail()
        }
        XCTAssertEqual(updated, try Fixtures.message("21-form-submitted.json"))
    }

    func testTypingReadAndCounters() throws {
        XCTAssertEqual(try Fixtures.event("36-event-typing.json").data, .typing(
            conversationId: "conv_5521",
            sender: Sender(type: .bot, id: "bot_default", name: "Clomni",
                           avatarUrl: URL(string: "https://app.clomni.ai/a/bot.png")),
            isTyping: true))
        XCTAssertEqual(try Fixtures.event("37-event-read.json").data,
                       .read(conversationId: "conv_5521", upToSeq: 12, by: .operator))
        XCTAssertEqual(try Fixtures.event("39-event-unread-changed.json").data, .unreadChanged(total: 2))
        XCTAssertEqual(try Fixtures.event("40-event-config-changed.json").data, .configChanged(etag: "W/\"7f3a\""))
    }

    func testConversationUpdated() throws {
        guard case .conversationUpdated(let update) = try Fixtures.event("38-event-conversation-updated.json").data else {
            return XCTFail()
        }
        XCTAssertEqual(update.id, "conv_5521")
        XCTAssertEqual(update.status, .open)
        XCTAssertEqual(update.assignee?.name, "Leyla")
        XCTAssertEqual(update.assignee?.avatarUrl?.absoluteString, "https://app.clomni.ai/a/leyla.png")
        XCTAssertEqual(update.assignee?.online, true)
        XCTAssertEqual(update.unreadCount, 1)

        let queued = ProtocolJSON.parseEvent(#"{"event":"conversation.updated","data":{"id":"conv_1","status":"snoozed","assignee":null},"ts":"2026-10-01T10:30:01Z"}"#)
        guard case .conversationUpdated(let bare)? = queued?.data else { return XCTFail() }
        XCTAssertEqual(bare.status, .unknown)
        XCTAssertNil(bare.assignee)
        XCTAssertNil(bare.unreadCount)
    }

    func testUnknownEventIsIgnored() throws {
        let event = try Fixtures.event("41-event-unknown.json")
        XCTAssertEqual(event.event, "conversation.rated")
        XCTAssertEqual(event.data, .unknown(name: "conversation.rated"))
        XCTAssertTrue(log.contains("unknown event \"conversation.rated\" ignored"), "\(log.lines)")
    }

    func testBrokenKnownEventsAreIgnored() {
        let frames = [
            #"{"event":"message.created","data":{"id":"msg_1"},"ts":"2026-10-01T10:30:01Z"}"#,
            #"{"event":"typing","data":{"conversation_id":"conv_1","sender":{"type":"bot"},"state":"maybe"}}"#,
            #"{"event":"read","data":{"conversation_id":"conv_1","by":"operator"}}"#,
            #"{"event":"unread.changed","data":{"total":"two"}}"#,
        ]
        for frame in frames {
            let event = ProtocolJSON.parseEvent(frame)
            XCTAssertEqual(event?.data.kind, "unknown", frame)
        }
        XCTAssertEqual(log.lines.count, frames.count, "\(log.lines)")
    }

    func testFramesThatAreNotEvents() {
        XCTAssertNil(ProtocolJSON.parseEvent("not json"))
        XCTAssertNil(ProtocolJSON.parseEvent(#"{"data":{}}"#))
        XCTAssertNil(ProtocolJSON.parseEvent("[1,2]"))
        XCTAssertNil(ProtocolJSON.parseEvent(#"{"event":"ready","data":{"user_id":"usr_1","heartbeat_sec":25},"ts":"later"}"#)?.ts)
    }
}

final class MessengerConfigTests: ProtocolTestCase {
    func testAparConfig() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("42-config-apar.json")))
        XCTAssertEqual(config.version, 12)
        XCTAssertEqual(config.brand.name, "Apar")
        XCTAssertEqual(config.brand.logoUrl?.absoluteString, "https://app.clomni.ai/v1/images/img_Lq3T8vXw2KpA9mZc4RbN")
        XCTAssertNil(config.brand.logoDarkUrl)
        XCTAssertEqual(config.brand.primaryColor, "#1F9D63")
        XCTAssertEqual(config.brand.headerStyle, .gradient)
        XCTAssertNil(config.brand.headerImageUrl)
        XCTAssertFalse(config.brand.glow)
        XCTAssertEqual(config.brand.colors?.light, MessengerConfig.Palette(
            primary: "#1F9D63", onPrimary: "#000000", primarySoft: "#E9F5EF", primaryLine: "#CEE9DD",
            headerFrom: "#1F9D63", headerTo: "#177248", headerText: "#FFFFFF"))
        XCTAssertEqual(config.brand.colors?.dark.primary, "#27C87E")
        XCTAssertEqual(config.team.show, true)
        XCTAssertEqual(config.team.avatars.count, 3)
        XCTAssertEqual(config.team.replyTime, "Adətən bir neçə dəqiqəyə cavab veririk")
        XCTAssertEqual(config.team.replyTimeOffline, "Hazırda iş saatı deyil, sizə səhər cavab verəcəyik")
        XCTAssertEqual(config.team.officeHours, MessengerConfig.OfficeHours(timeZone: "Asia/Baku", openNow: true,
                                                                            nextOpenAt: nil))
        XCTAssertEqual(config.bot, MessengerConfig.Bot(name: "Clomni", avatarUrl: nil))
        XCTAssertEqual(config.home.cards, [.send, .recent, .channels])
        XCTAssertEqual(config.home.channels.map(\.type), ["instagram", "whatsapp", "linkedin", "email"])
        XCTAssertEqual(config.theme, MessengerConfig.Theme(
            mode: .system, launcher: MessengerConfig.Launcher(enabled: false, position: .right, bottomPadding: 20)))
        XCTAssertEqual(config.composer, MessengerConfig.Composer(attachments: true, emoji: true))
        XCTAssertEqual(config.languages, ["az", "en", "ru"])
        XCTAssertEqual(config.strings["send_card_title"], "Bizə mesaj göndərin")
        XCTAssertEqual(config.strings["greeting_line1"], "Salam, {first_name}")
        XCTAssertEqual(config.limits, MessengerConfig.Limits(imageMb: 10, fileMb: 25, textChars: 4000))
        XCTAssertTrue(config.poweredBy)
    }

    /// APPEARANCE-CONTRACT § 4a and DESIGN-PASS: the full logo and the greeting's size.
    func testWordmarkAndTitleSize() throws {
        let wordmark = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Clomni","logo_style":"wordmark","wordmark_url":"https://app.clomni.ai/v1/images/img_w",
                      "wordmark_dark_url":"https://app.clomni.ai/v1/images/img_wd"},
             "home":{"title_size":"l"}}
            """##.utf8)))
        XCTAssertEqual(wordmark.brand.logoStyle, .wordmark)
        XCTAssertEqual(wordmark.brand.wordmarkUrl?.absoluteString, "https://app.clomni.ai/v1/images/img_w")
        XCTAssertEqual(wordmark.brand.wordmarkDarkUrl?.absoluteString, "https://app.clomni.ai/v1/images/img_wd")
        XCTAssertEqual(wordmark.home.titleSize, .l)

        let small = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"home":{"title_size":"s"}}"#.utf8)))
        XCTAssertEqual(small.home.titleSize, .s)
        // Without a wordmark there is nothing to show: mark. Unknown values take the defaults.
        let odd = try XCTUnwrap(ProtocolJSON.parseConfig(Data(
            #"{"brand":{"logo_style":"wordmark","wordmark_url":null},"home":{"title_size":"xl"}}"#.utf8)))
        XCTAssertEqual(odd.brand.logoStyle, .mark)
        XCTAssertEqual(odd.home.titleSize, .m)
        let neon = try XCTUnwrap(ProtocolJSON.parseConfig(Data(
            #"{"brand":{"logo_style":"neon","wordmark_url":"https://a.az/w.png"}}"#.utf8)))
        XCTAssertEqual(neon.brand.logoStyle, .mark)
        // The server's fixtures: 59 with a wordmark and the large greeting, 42 and 58 without.
        let fixture = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("59-config-wordmark.json")))
        XCTAssertEqual(fixture.brand.logoStyle, .wordmark)
        XCTAssertEqual(fixture.brand.wordmarkUrl?.absoluteString, "https://app.clomni.ai/v1/images/img_Wm7Qk2Lx9PzR4sTv8NcY")
        XCTAssertNil(fixture.brand.wordmarkDarkUrl)
        XCTAssertEqual(fixture.home.titleSize, .l)
        for name in ["42-config-apar.json", "58-config-apar-en.json"] {
            let apar = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data(name)))
            XCTAssertEqual(apar.brand.logoStyle, .mark, name)
            XCTAssertNil(apar.brand.wordmarkUrl, name)
            XCTAssertEqual(apar.home.titleSize, .m, name)
        }
        // A server that does not send the fields at all.
        let older = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"brand":{"name":"Apar"},"home":{}}"#.utf8)))
        XCTAssertEqual(older.brand.logoStyle, .mark)
        XCTAssertEqual(older.home.titleSize, .m)
    }

    func testMinimalConfigTakesDefaults() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("43-config-minimal.json")))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.brand.name, "Clomni, Inc.")
        XCTAssertEqual(config.brand.primaryColor, "#10A670")
        XCTAssertNil(config.brand.logoUrl)
        XCTAssertNil(config.brand.logoDarkUrl)
        XCTAssertEqual(config.brand.colors?.dark.headerText, "#1B1D21", "light green: dark text")
        XCTAssertEqual(config.brand.headerStyle, .solid)
        XCTAssertEqual(config.theme, MessengerConfig.Theme(
            mode: .system, launcher: MessengerConfig.Launcher(enabled: false, position: .right, bottomPadding: 20)))
        XCTAssertEqual(config.home.cards, [.send])
        XCTAssertTrue(config.home.channels.isEmpty)
        XCTAssertEqual(config.team, MessengerConfig.Team(
            show: false, avatars: [], replyTime: "Adətən bir neçə dəqiqəyə cavab veririk",
            replyTimeOffline: "Hazırda iş saatı deyil, iş saatında cavab verəcəyik",
            officeHours: MessengerConfig.OfficeHours(timeZone: nil, openNow: true, nextOpenAt: nil)))
        XCTAssertEqual(config.bot, MessengerConfig.Bot(name: "Clomni", avatarUrl: nil))
        XCTAssertEqual(config.languages, ["az"])
        XCTAssertTrue(config.strings.isEmpty)
        XCTAssertTrue(config.poweredBy)
    }

    func testEmptyAndOddConfigs() throws {
        let empty = try XCTUnwrap(ProtocolJSON.parseConfig(Data("{}".utf8)))
        XCTAssertEqual(empty.version, 0)
        XCTAssertEqual(empty.brand.name, "")
        XCTAssertEqual(empty.home.cards, [.send, .recent, .channels], "no list: every card")
        XCTAssertEqual(empty.languages, ["az"])

        let odd = try XCTUnwrap(ProtocolJSON.parseConfig(Data(##"""
        {"brand":{"name":"X","primary_color":"#12345","header_style":"neon","glow":"yes",
                  "colors":{"light":{"primary":"#1F9D63"},"dark":{}}},
         "theme":{"mode":"neon","launcher":{"enabled":true,"position":"left","bottom_padding":500}},
         "home":{"channels":[{"type":"x"},{"type":"tiktok","url":"https://tiktok.com/@x"},
                             {"type":"a","url":"https://a.az"},{"type":"b","url":"https://b.az"},
                             {"type":"c","url":"https://c.az"},{"type":"d","url":"https://d.az"},
                             {"type":"e","url":"https://e.az"}],
                 "cards":["channels","promo","recent","channels"]},
         "team":{"show":false,"avatars":["https://a/1.png",7],"office_hours":{"tz":"Asia/Baku"}},
         "strings":{"send":"Göndər","count":3},"languages":[],"limits":{"image_mb":0,"file_mb":5},
         "powered_by":false}
        """##.utf8)))
        XCTAssertEqual(odd.brand.primaryColor, MessengerConfig.Brand.defaultPrimaryColor)
        for bad in ["#+12345", "#１Ｆ９Ｄ６３", "#1F9D6Z", "1F9D63A"] {
            let config = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"{"brand":{"primary_color":"\#(bad)"}}"#.utf8)))
            XCTAssertEqual(config.brand.primaryColor, MessengerConfig.Brand.defaultPrimaryColor, bad)
        }
        XCTAssertEqual(odd.brand.headerStyle, .gradient)
        XCTAssertFalse(odd.brand.glow)
        XCTAssertNil(odd.brand.colors, "an incomplete set is no set")
        XCTAssertEqual(odd.theme, MessengerConfig.Theme(
            mode: .system, launcher: MessengerConfig.Launcher(enabled: true, position: .left, bottomPadding: 20)))
        XCTAssertEqual(odd.home.channels.map(\.type), ["tiktok", "a", "b", "c", "d"], "at most five")
        XCTAssertEqual(odd.home.cards, [.send, .channels, .recent], "send always, each card once, in order")
        XCTAssertFalse(odd.team.show)
        XCTAssertEqual(odd.team.avatars.count, 1)
        XCTAssertEqual(odd.team.officeHours?.openNow, true)
        XCTAssertFalse(odd.poweredBy)
        let closed = try XCTUnwrap(ProtocolJSON.parseConfig(Data(
            #"{"team":{"office_hours":{"open_now":false,"next_open_at":"2026-10-02T05:00:00Z"}}}"#.utf8)))
        XCTAssertEqual(closed.team.officeHours?.nextOpenAt, Date(timeIntervalSince1970: 1_790_917_200))
        XCTAssertFalse(closed.team.officeHours?.openNow ?? true)
        XCTAssertEqual(odd.strings, ["send": "Göndər"])
        XCTAssertEqual(odd.languages, ["az"])
        XCTAssertEqual(odd.limits, MessengerConfig.Limits(imageMb: 10, fileMb: 5, textChars: 4000))

        let image = try XCTUnwrap(ProtocolJSON.parseConfig(Data(
            #"{"brand":{"header_style":"image","header_image_url":"https://app.clomni.ai/v1/images/h","glow":true}}"#.utf8)))
        XCTAssertEqual(image.brand.headerStyle, .image)
        XCTAssertEqual(image.brand.headerImageUrl?.absoluteString, "https://app.clomni.ai/v1/images/h")
        XCTAssertTrue(image.brand.glow)
    }

    func testNotAConfig() {
        XCTAssertNil(ProtocolJSON.parseConfig(Data("<html>".utf8)))
        XCTAssertNil(ProtocolJSON.parseConfig(Data("[]".utf8)))
        XCTAssertTrue(log.contains("config: not JSON, dropped"), "\(log.lines)")
    }
}

final class PushPayloadTests: ProtocolTestCase {
    private let expected = PushPayload(type: "message", conversationId: "conv_5521", messageId: "msg_f02",
                                       title: "Leyla · Apar", body: "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
                                       avatarUrl: URL(string: "https://app.clomni.ai/a/leyla.png"), unreadTotal: 1)

    func testPushFixture() throws {
        XCTAssertEqual(ProtocolJSON.parsePush(try Fixtures.data("44-push-message.json")), expected)
    }

    func testApnsUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Leyla · Apar", "body": "…"], "sound": "default", "badge": 1] as [String: Any],
            "clomni": "1", "type": "message", "conversation_id": "conv_5521", "message_id": "msg_f02",
            "title": "Leyla · Apar", "body": "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
            "avatar_url": "https://app.clomni.ai/a/leyla.png", "unread_total": 1, 42: "a key that is not a string",
        ]
        XCTAssertEqual(ProtocolJSON.parsePush(userInfo), expected)
    }

    func testCountSentAsTextAndMissingOptionals() throws {
        let push = ProtocolJSON.parsePush(["clomni": "1", "type": "message", "conversation_id": "conv_1", "title": "T",
                                           "body": "B", "unread_total": "3", "avatar_url": NSNull()] as [AnyHashable: Any])
        XCTAssertEqual(push?.unreadTotal, 3)
        XCTAssertNil(push?.messageId)
        XCTAssertNil(push?.avatarUrl)
    }

    func testOtherPushesAreNotClomni() {
        XCTAssertTrue(ProtocolJSON.isClomniPush(["aps": [:] as [String: Any], "clomni": "1"] as [AnyHashable: Any]))
        XCTAssertFalse(ProtocolJSON.isClomniPush(["aps": ["alert": "Your order shipped"] as [String: Any]] as [AnyHashable: Any]))
        XCTAssertFalse(ProtocolJSON.isClomniPush(["clomni": "2"] as [AnyHashable: Any]))
        XCTAssertFalse(ProtocolJSON.isClomniPush(["clomni": 1] as [AnyHashable: Any]))
        XCTAssertNil(ProtocolJSON.parsePush(["aps": ["alert": "Your order shipped"] as [String: Any], "order": 7] as [AnyHashable: Any]))
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "2", "type": "message", "conversation_id": "c", "title": "T",
                                             "body": "B"] as [AnyHashable: Any]))
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "1", "type": "message"] as [AnyHashable: Any]))
        // JSONSerialization raises an Objective-C exception on NaN unless it is checked first.
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "1", "unread_total": Double.nan] as [AnyHashable: Any]))
    }
}
