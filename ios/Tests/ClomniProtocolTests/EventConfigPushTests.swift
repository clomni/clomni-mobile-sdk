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
        XCTAssertEqual(config.brand.name, "Apar")
        XCTAssertEqual(config.brand.logoUrl?.absoluteString, "https://app.clomni.ai/a/apar.png")
        XCTAssertEqual(config.brand.primaryColor, "#1F9D63")
        XCTAssertEqual(config.brand.onPrimaryColor, "#FFFFFF")
        XCTAssertEqual(config.brand.theme, .system)
        XCTAssertFalse(config.launcher.visible)
        XCTAssertEqual(config.launcher.position, .right)
        XCTAssertEqual(config.launcher.bottomPadding, 20)
        XCTAssertEqual(config.launcher.icon, "default")
        XCTAssertEqual(config.home.greetingTitle, "Necə kömək edə bilərik?")
        XCTAssertEqual(config.home.greetingSubtitle, "Bizdən nəsə soruşun və ya fikrinizi bildirin")
        XCTAssertTrue(config.home.showTeamAvatars)
        XCTAssertEqual(config.home.channels.map(\.type), ["instagram", "whatsapp", "linkedin", "email"])
        XCTAssertEqual(config.home.channels.last?.url.absoluteString, "mailto:support@apar.az")
        XCTAssertEqual(config.home.cards, [.recentConversation, .newConversation])
        XCTAssertEqual(config.team.avatars.count, 3)
        XCTAssertEqual(config.team.replyTime, "Adətən bir neçə dəqiqəyə cavab veririk")
        XCTAssertEqual(config.team.officeHours, MessengerConfig.OfficeHours(timeZone: "Asia/Baku", openNow: true))
        XCTAssertEqual(config.bot.name, "Clomni")
        XCTAssertEqual(config.bot.avatarUrl?.absoluteString, "https://app.clomni.ai/a/bot.png")
        XCTAssertEqual(config.composer.placeholder, "Mesaj yazın…")
        XCTAssertTrue(config.composer.attachments)
        XCTAssertTrue(config.composer.emoji)
        XCTAssertEqual(config.languages, ["az", "en", "ru"])
        XCTAssertEqual(config.strings["choose_above"], "Yuxarıdakı variantlardan birini seçin")
        XCTAssertEqual(config.strings.count, 7)
        XCTAssertEqual(config.limits, MessengerConfig.Limits(imageMb: 10, fileMb: 25, textChars: 4000))
    }

    func testMinimalConfigTakesDefaults() throws {
        let config = try XCTUnwrap(ProtocolJSON.parseConfig(try Fixtures.data("43-config-minimal.json")))
        XCTAssertEqual(config.brand.name, "Clomni, Inc.")
        XCTAssertEqual(config.brand.primaryColor, "#10A670")
        XCTAssertNil(config.brand.logoUrl)
        XCTAssertNil(config.brand.onPrimaryColor)
        XCTAssertEqual(config.brand.theme, .system)
        XCTAssertEqual(config.launcher, MessengerConfig.Launcher(visible: false, position: .right, bottomPadding: 20,
                                                                 icon: "default"))
        XCTAssertNil(config.home.greetingTitle)
        XCTAssertTrue(config.home.channels.isEmpty)
        XCTAssertEqual(config.home.cards, [.newConversation])
        XCTAssertEqual(config.team, MessengerConfig.Team(avatars: [], replyTime: nil, officeHours: nil))
        XCTAssertEqual(config.bot, MessengerConfig.Bot(name: "Clomni", avatarUrl: nil))
        XCTAssertEqual(config.composer, MessengerConfig.Composer(placeholder: nil, attachments: true, emoji: true))
        XCTAssertEqual(config.languages, ["az"])
        XCTAssertTrue(config.strings.isEmpty)
        XCTAssertEqual(config.limits, MessengerConfig.Limits(imageMb: 10, fileMb: 25, textChars: 4000))
    }

    func testEmptyAndOddConfigs() throws {
        let empty = try XCTUnwrap(ProtocolJSON.parseConfig(Data("{}".utf8)))
        XCTAssertEqual(empty.brand.name, "")
        XCTAssertEqual(empty.home.cards, [.recentConversation, .newConversation])
        XCTAssertEqual(empty.languages, ["az"])

        let odd = try XCTUnwrap(ProtocolJSON.parseConfig(Data(#"""
        {"brand":{"name":"X","primary_color":"#12345","on_primary_color":"#abcdef","theme":"neon"},
         "launcher":{"visible":true,"position":"left","bottom_padding":-4},
         "home":{"channels":[{"type":"x"},{"type":"tiktok","url":"https://tiktok.com/@x"}],"cards":["promo","new_conversation"]},
         "team":{"avatars":["https://a/1.png",7],"office_hours":{"tz":"Asia/Baku"}},
         "strings":{"send":"Göndər","count":3},"languages":[],"limits":{"image_mb":0,"file_mb":5}}
        """#.utf8)))
        XCTAssertEqual(odd.brand.primaryColor, MessengerConfig.Brand.defaultPrimaryColor)
        XCTAssertEqual(odd.brand.onPrimaryColor, "#abcdef")
        XCTAssertEqual(odd.brand.theme, .system)
        XCTAssertEqual(odd.launcher, MessengerConfig.Launcher(visible: true, position: .left, bottomPadding: 20,
                                                              icon: "default"))
        XCTAssertEqual(odd.home.channels.map(\.type), ["tiktok"])
        XCTAssertEqual(odd.home.cards, [.newConversation])
        XCTAssertEqual(odd.team.avatars.count, 1)
        XCTAssertEqual(odd.team.officeHours?.openNow, true)
        XCTAssertEqual(odd.strings, ["send": "Göndər"])
        XCTAssertEqual(odd.languages, ["az"])
        XCTAssertEqual(odd.limits, MessengerConfig.Limits(imageMb: 10, fileMb: 5, textChars: 4000))
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
        XCTAssertNil(ProtocolJSON.parsePush(["aps": ["alert": "Your order shipped"] as [String: Any], "order": 7] as [AnyHashable: Any]))
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "2", "type": "message", "conversation_id": "c", "title": "T",
                                             "body": "B"] as [AnyHashable: Any]))
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "1", "type": "message"] as [AnyHashable: Any]))
        // JSONSerialization raises an Objective-C exception on NaN unless it is checked first.
        XCTAssertNil(ProtocolJSON.parsePush(["clomni": "1", "unread_total": Double.nan] as [AnyHashable: Any]))
    }
}
