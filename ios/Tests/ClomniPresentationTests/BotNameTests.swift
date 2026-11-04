import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

/// CM-346: a bot (a flow, Clomni AI, an AgentBot) shows as the server names it: the sender's name and picture, else
/// the panel's bot (config.bot), else the brand and its logo. TestFlight #19 showed the brand ("Clomni") over the
/// flow's messages while the panel's bot was "qweq". The same everywhere: the bubbles, the quote, typing, Home's
/// "Ən son mesaj" and the conversations' list.
final class BotNameTests: XCTestCase {
    /// 2026-10-01T10:32:00Z, two minutes after the fixtures' messages.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!
    private let senderPicture = URL(string: "https://app.clomni.ai/a/qweq.png")!
    private let botPicture = URL(string: "https://app.clomni.ai/v1/images/bot")!
    private let logo = URL(string: "https://app.clomni.ai/v1/images/logo")!

    /// The brand "Example", with its logo unless `logo` is false; the panel's bot named `bot`, with its picture
    /// unless `picture` is false.
    private func config(bot: String, picture: Bool = true, logo: Bool = true) -> MessengerConfig {
        let logoUrl = logo ? #","logo_url":"\#(self.logo)""# : ""
        let botUrl = picture ? #","avatar_url":"\#(botPicture)""# : ""
        return ProtocolJSON.parseConfig(Data(
            #"{"brand":{"name":"Example"\#(logoUrl)},"bot":{"name":"\#(bot)"\#(botUrl)}}"#.utf8))!
    }

    /// The bot as a message's sender: with a name and a picture, or without.
    private func sender(_ name: String?, picture: Bool) -> JSONValue {
        var fields: [String: JSONValue] = ["type": "bot", "id": "bot_default"]
        if let name { fields["name"] = .string(name) }
        if picture { fields["avatar_url"] = .string(senderPicture.absoluteString) }
        return .object(fields)
    }

    private func botMessage(_ name: String?, picture: Bool) -> Message {
        Fixture.message("01-text-bot.json", ["id": "msg_b", "seq": 1, "sender": sender(name, picture: picture)])
    }

    private func chat(_ messages: [Message], _ config: MessengerConfig,
                      _ build: (inout ChatSnapshot) -> Void = { _ in }) -> ChatScreen {
        var snapshot = ChatSnapshot(config: config, conversation: Fixture.conversation(status: "open"), messages: messages)
        snapshot.load = .loaded
        build(&snapshot)
        return ChatPresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now).screen(snapshot)
    }

    private func bubbles(_ screen: ChatScreen) -> [Bubble] {
        screen.items.compactMap { if case .bubble(let bubble) = $0 { return bubble }; return nil }
    }

    func testTheBotsNameAndPictureOverItsBubbles() {
        let panel = config(bot: "Köməkçi")
        let named = bubbles(chat([botMessage("qweq", picture: true)], panel)).first
        XCTAssertEqual(named?.nameLine, "qweq", "the server's name for the bot")
        XCTAssertEqual(named?.avatar, ChatAvatar(url: senderPicture, initial: "Q", isBot: true))
        XCTAssertEqual(named?.accessibilityLabel.hasPrefix("qweq bot, 10:30: "), true, named?.accessibilityLabel ?? "")

        let unnamed = bubbles(chat([botMessage(nil, picture: false)], panel)).first
        XCTAssertEqual(unnamed?.nameLine, "Köməkçi", "no name from the server: the panel's bot")
        XCTAssertEqual(unnamed?.avatar, ChatAvatar(url: botPicture, initial: "K", isBot: true))
        XCTAssertEqual(bubbles(chat([botMessage("", picture: false)], panel)).first?.nameLine, "Köməkçi",
                       "an empty name is none")

        let brand = bubbles(chat([botMessage(nil, picture: false)], config(bot: "", picture: false))).first
        XCTAssertEqual(brand?.nameLine, "Example", "no bot name anywhere: the brand")
        XCTAssertEqual(brand?.avatar, ChatAvatar(url: logo, initial: "E", isBot: true), "and its logo")
        let bare = bubbles(chat([botMessage(nil, picture: false)], config(bot: "", picture: false, logo: false))).first
        XCTAssertEqual(bare?.avatar, ChatAvatar(url: nil, initial: "E", isBot: true), "no logo either: the initial")
    }

    func testTheBotsNameInQuotesAndTyping() {
        let panel = config(bot: "Köməkçi")
        let bot = botMessage(nil, picture: false)
        let answer = Fixture.message("03-text-user.json", [
            "id": "msg_u", "seq": 2,
            "reply_to": ["id": "msg_b", "sender": ["type": "bot"], "excerpt": "Salam!", "kind": "text"],
        ])
        XCTAssertEqual(bubbles(chat([bot, answer], panel)).last?.quote?.author, "Köməkçi", "the server's quote")
        XCTAssertEqual(chat([bot], panel) { $0.replyingTo = "msg_b" }.composer.quote?.author, "Köməkçi",
                       "over the field while answering it")

        let typing = chat([bot], panel) { $0.typing = Sender(type: .bot, name: "qweq", avatarUrl: self.senderPicture) }
        guard case .typing(let line)? = typing.items.last else { return XCTFail("\(typing.items)") }
        XCTAssertEqual(line.accessibilityLabel, "qweq yazır")
        XCTAssertEqual(line.avatar, ChatAvatar(url: senderPicture, initial: "Q", isBot: true))
        let unnamed = chat([bot], panel) { $0.typing = Sender(type: .bot) }
        guard case .typing(let panelLine)? = unnamed.items.last else { return XCTFail("\(unnamed.items)") }
        XCTAssertEqual(panelLine.accessibilityLabel, "Köməkçi yazır")
        XCTAssertEqual(panelLine.avatar.url, botPicture)
    }

    func testTheBotsNameOnHomeAndInTheConversations() throws {
        func screens(_ name: String?, picture: Bool, _ config: MessengerConfig) throws -> (row: ConversationRow,
                                                                                          recent: ConversationRow?) {
            let json = ProtocolJSON.encode(sender(name, picture: picture))
            let conversation = Fixture.conversation("conv_1", message: "01-text-bot.json") {
                $0.replacingOccurrences(of: #""sender": \{[^}]*\}"#, with: #""sender": \#(String(decoding: json, as: UTF8.self))"#,
                                        options: .regularExpression)
            }
            var snapshot = MessengerSnapshot(config: config, conversations: [conversation])
            snapshot.configLoad = .loaded
            snapshot.conversationsLoad = .loaded
            let presenter = HomePresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now)
            return (try XCTUnwrap(presenter.messages(snapshot).rows.first), presenter.home(snapshot).recent?.row)
        }
        let panel = config(bot: "Köməkçi")

        let named = try screens("qweq", picture: true, panel)
        XCTAssertEqual(named.row.detail, "qweq · 2 dəq", "the server's name for the bot")
        XCTAssertEqual(named.row.avatarUrl, senderPicture)
        XCTAssertEqual(named.row.initial, "Q")
        XCTAssertEqual(named.recent, named.row, "Home's \"Ən son mesaj\" the same")

        let unnamed = try screens(nil, picture: false, panel)
        XCTAssertEqual(unnamed.row.detail, "Köməkçi · 2 dəq", "no name from the server: the panel's bot")
        XCTAssertEqual(unnamed.row.avatarUrl, botPicture)

        let brand = try screens(nil, picture: false, config(bot: "", picture: false))
        XCTAssertEqual(brand.row.detail, "Example · 2 dəq", "no bot name anywhere: the brand")
        XCTAssertEqual(brand.row.avatarUrl, logo)
        XCTAssertEqual(brand.row.initial, "E")
        XCTAssertNil(try screens(nil, picture: false, config(bot: "", picture: false, logo: false)).row.avatarUrl)
    }
}
