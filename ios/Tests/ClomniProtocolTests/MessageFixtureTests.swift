import Foundation
import XCTest
@testable import ClomniProtocol

/// What each server → client fixture must read as; the notes in protocol/fixtures/index.json say why.
final class MessageFixtureTests: ProtocolTestCase {
    private let tenThirty = Date(timeIntervalSince1970: 1_790_850_600) // 2026-10-01T10:30:00Z

    func testBotTextFromAFlow() throws {
        let message = try Fixtures.message("01-text-bot.json")
        XCTAssertEqual(message.id, "msg_f01")
        XCTAssertNil(message.clientId)
        XCTAssertEqual(message.conversationId, "conv_5521")
        XCTAssertEqual(message.sender, Sender(type: .bot, id: "bot_default", name: "Clomni",
                                              avatarUrl: URL(string: "https://app.clomni.ai/a/bot.png")))
        XCTAssertEqual(message.createdAt, tenThirty)
        XCTAssertEqual(message.seq, 1)
        XCTAssertEqual(message.lang, "az")
        XCTAssertEqual(message.flow, FlowRef(flowId: "flw_example_az", nodeId: "A0", version: 7, interactive: false))
        XCTAssertEqual(message.content, .text("Salam! Siz Example şirkətinin dəstək bölməsi ilə əlaqəyə keçmisiniz."))
        XCTAssertTrue(log.lines.isEmpty, "\(log.lines)")
    }

    func testTimesWithAndWithoutMilliseconds() throws {
        XCTAssertEqual(try Fixtures.message("s5.1-envelope.json", in: "examples/brief").createdAt, tenThirty)
        let raw = try Fixtures.json("01-text-bot.json")
        let withMillis = try XCTUnwrap(ProtocolJSON.parseMessage(raw.setting("created_at", "2026-10-01T10:30:00.250Z")))
        XCTAssertEqual(withMillis.createdAt.timeIntervalSince(tenThirty), 0.25, accuracy: 0.0001)
        XCTAssertNil(ProtocolJSON.parseMessage(raw.setting("created_at", "1 October 2026")))
    }

    func testOperatorMarkdownArrivesAsIs() throws {
        let message = try Fixtures.message("02-text-operator-markdown.json")
        XCTAssertEqual(message.sender.type, .operator)
        XCTAssertNil(message.flow)
        // Rendering the limited markdown is the UI's job; the protocol keeps the text exactly.
        XCTAssertEqual(message.content, .text("**Gedişinizi yoxladıq.** Balansınıza *2 AZN* qaytarıldı.\nƏtraflı: [şərtlər](https://example.com/sertler)"))
    }

    func testUserTextCarriesItsClientId() throws {
        let message = try Fixtures.message("03-text-user.json")
        XCTAssertEqual(message.sender.type, .user)
        XCTAssertEqual(message.clientId, "6f1c2c8e-1b2a-4c3d-8e9f-0a1b2c3d4e5f")
        XCTAssertNil(message.sender.avatarUrl)
    }

    func testLongEmojiAndUnsafeLinkTextsAreKeptWhole() throws {
        guard case .text(let long) = try Fixtures.message("04-text-long.json").content else { return XCTFail() }
        XCTAssertEqual(long.count, 635)
        XCTAssertEqual(try Fixtures.message("05-text-emoji-only.json").content, .text("👍🙏"))
        guard case .text(let unsafe) = try Fixtures.message("06-text-unsafe-link.json").content else { return XCTFail() }
        XCTAssertTrue(unsafe.contains("[oyun](javascript:alert(1))"))
    }

    func testLanguageChoiceBeforeAndAfter() throws {
        let before = try Fixtures.message("07-language-select.json")
        let replies = try XCTUnwrap(before.content.quickReplies)
        XCTAssertEqual(replies.buttons.map(\.icon), ["🇦🇿", "🇬🇧", "🇷🇺"])
        XCTAssertEqual(replies.buttons.map(\.payload), ["set_lang:az", "set_lang:en", "set_lang:ru"])
        XCTAssertEqual(replies.buttons.first, MessageContent.Button(id: "az", title: "Azərbaycan dili", icon: "🇦🇿",
                                                                    payload: "set_lang:az"))
        XCTAssertEqual(replies.layout, .vertical)
        XCTAssertFalse(replies.inputDisabled)
        XCTAssertEqual(before.flow?.interactive, true)

        let after = try Fixtures.message("08-language-select-answered.json")
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.flow?.interactive, false)
        XCTAssertEqual(after.content, before.content)
    }

    func testExampleFlowLevels() throws {
        let level1 = try XCTUnwrap(try Fixtures.message("09-example-level1-A.json").content.quickReplies)
        XCTAssertTrue(level1.inputDisabled)
        XCTAssertFalse(level1.allowBack)
        XCTAssertEqual(level1.buttons.map(\.payload), ["node:S", "node:R"])
        XCTAssertNil(level1.buttons[0].icon)

        let level2 = try XCTUnwrap(try Fixtures.message("10-example-level2-S-chips.json").content.quickReplies)
        XCTAssertEqual(level2.layout, .chips)
        XCTAssertTrue(level2.allowBack)
        XCTAssertEqual(level2.buttons.count, 5)

        let level3 = try XCTUnwrap(try Fixtures.message("11-example-level3-U.json").content.quickReplies)
        XCTAssertEqual(level3.layout, .vertical)
        XCTAssertTrue(level3.allowBack)

        let level4 = try XCTUnwrap(try Fixtures.message("12-example-level4-handoff.json").content.quickReplies)
        XCTAssertEqual(level4.buttons.map(\.payload), ["handoff", "end"])

        let end = try Fixtures.message("50-example-end.json")
        XCTAssertEqual(end.flow?.nodeId, "END")
        XCTAssertEqual(end.flow?.interactive, false)
        XCTAssertEqual(end.content.kind, "text")
    }

    func testButtonTitleOverEightyIsKeptWhole() throws {
        let replies = try XCTUnwrap(try Fixtures.message("13-button-title-over-80.json").content.quickReplies)
        let raw = try Fixtures.json("13-button-title-over-80.json")
        XCTAssertEqual(replies.buttons[0].title, raw["content"]?["buttons"]?.arrayValue?.first?["title"]?.stringValue)
        XCTAssertEqual(replies.buttons[0].title.count, 112)
    }

    func testTenButtonsAndButtonsWithoutText() throws {
        let ten = try XCTUnwrap(try Fixtures.message("14-ten-buttons.json").content.quickReplies)
        XCTAssertEqual(ten.buttons.count, 10)
        XCTAssertEqual(ten.buttons.last?.id, "o_10")

        let bare = try XCTUnwrap(try Fixtures.message("15-quick-replies-no-text.json").content.quickReplies)
        XCTAssertNil(bare.text)
        XCTAssertEqual(bare.layout, .vertical)
        XCTAssertFalse(bare.inputDisabled)
        XCTAssertFalse(bare.allowBack)
    }

    func testImages() throws {
        let image = try Fixtures.message("16-image.json")
        XCTAssertEqual(image.clientId, "3c2b1a09-8f7e-4d6c-9b5a-4f3e2d1c0b9a")
        XCTAssertEqual(image.content, .image(MessageContent.Image(
            url: try XCTUnwrap(URL(string: "https://app.clomni.ai/f/velo.jpg")),
            thumbUrl: URL(string: "https://app.clomni.ai/f/velo_480.jpg"), width: 1280, height: 960,
            caption: "Velosiped Nizami küçəsindədir")))

        let bare = try Fixtures.message("17-image-no-dimensions.json")
        XCTAssertEqual(bare.content, .image(MessageContent.Image(
            url: try XCTUnwrap(URL(string: "https://app.clomni.ai/f/receipt.png")))))
    }

    func testFile() throws {
        XCTAssertEqual(try Fixtures.message("18-file-pdf.json").content, .file(MessageContent.File(
            url: try XCTUnwrap(URL(string: "https://app.clomni.ai/f/qaime.pdf")), name: "qaime.pdf", size: 182_340,
            mime: "application/pdf")))
    }

    func testVoiceMessages() throws {
        let voice = try Fixtures.message("100-audio-voice-user.json")
        XCTAssertEqual(voice.content, .audio(MessageContent.Audio(
            url: try XCTUnwrap(URL(string: "https://app.clomni.ai/f/voice-7d1c.m4a")), mime: "audio/mp4", size: 96_412,
            durationMs: 14_260, waveform: ClientMessageTests.waveform)))
        XCTAssertEqual(try Fixtures.message("101-audio-operator-no-waveform.json").content, .audio(MessageContent.Audio(
            url: try XCTUnwrap(URL(string: "https://app.clomni.ai/f/cavab.mp3")), mime: "audio/mpeg", size: 381_220)))
        XCTAssertEqual(try Fixtures.message("104-reply-operator-to-voice.json").replyTo?.kind, "audio")
        XCTAssertTrue(log.lines.isEmpty, "\(log.lines)")

        func waveform(_ levels: String) -> [Int]? {
            let json = #"{"url":"https://a.b/v.m4a","mime":"audio/mp4","size":1,"waveform":"# + levels + "}"
            guard case .audio(let audio) = MessageContent(type: "audio", json: ProtocolJSON.decode(Data(json.utf8)) ?? .null) else { return [-1] }
            return audio.waveform
        }
        XCTAssertEqual(waveform("[0, 100, 7.0]"), [0, 100, 7])
        XCTAssertNil(waveform("[1.5]"))
        XCTAssertNil(waveform("[]"))
        XCTAssertNil(waveform(#"["5"]"#))
        XCTAssertNil(waveform("[" + Array(repeating: "5", count: 129).joined(separator: ",") + "]"))
        XCTAssertEqual(waveform("[" + Array(repeating: "5", count: 128).joined(separator: ",") + "]")?.count, 128)
        // Without its address or size it cannot play: the fallback text.
        XCTAssertEqual(MessageContent(type: "audio", json: ["mime": "audio/mp4", "size": 1]).kind, "unknown")
        XCTAssertEqual(MessageContent(type: "audio", json: ["url": "https://a.b/v.m4a", "mime": "audio/mp4"]).kind, "unknown")
        guard case .audio(let negative) = MessageContent(type: "audio", json: ["url": "https://a.b/v.m4a", "mime": "audio/mp4", "size": 1, "duration_ms": -1])
        else { return XCTFail() }
        XCTAssertNil(negative.durationMs)
    }

    func testForms() throws {
        let contact = try XCTUnwrap(try Fixtures.message("19-form-contact.json").content.form)
        XCTAssertEqual(contact.formId, "frm_contact")
        XCTAssertEqual(contact.submitTitle, "Göndər")
        XCTAssertNil(contact.submitted)
        XCTAssertEqual(contact.fields.map(\.key), ["name", "phone", "email"])
        XCTAssertEqual(contact.fields[0].maxLength, 80)
        XCTAssertEqual(contact.fields[1].defaultCountry, "AZ")
        XCTAssertEqual(contact.fields.map(\.required), [true, true, false])

        let all = try XCTUnwrap(try Fixtures.message("20-form-all-field-types.json").content.form)
        XCTAssertEqual(all.fields.map(\.type), [.text, .textarea, .phone, .email, .number, .select, .date])
        XCTAssertEqual(all.fields[5].options.map(\.label), ["Bakı", "Gəncə", "Sumqayıt"])
        XCTAssertEqual(all.fields[5].options.first?.value, "baku")
        XCTAssertTrue(all.fields[0].options.isEmpty)

        let sent = try Fixtures.message("21-form-submitted.json")
        XCTAssertEqual(sent.seq, 18)
        XCTAssertEqual(sent.flow?.interactive, false)
        XCTAssertEqual(sent.content.form?.submitted, ["name": "Aysel Məmmədova", "phone": "+994501234567",
                                                      "email": "aysel@example.com"])
    }

    func testSystemMessages() throws {
        let queue = try XCTUnwrap(try Fixtures.message("22-system-waiting-in-queue.json").content.system)
        XCTAssertEqual(queue.event, .waitingInQueue)
        XCTAssertEqual(queue.position, 3)
        XCTAssertEqual(try Fixtures.message("22-system-waiting-in-queue.json").sender, Sender(type: .system))

        XCTAssertEqual(try Fixtures.message("23-system-operator-joined.json").content.system?.event, .operatorJoined)
        XCTAssertEqual(try Fixtures.message("24-system-conversation-closed.json").content.system?.event, .conversationClosed)

        let unknown = try XCTUnwrap(try Fixtures.message("25-system-unknown-event.json").content.system)
        XCTAssertEqual(unknown.event, .unknown("survey_scheduled"))
        XCTAssertEqual(unknown.text, "Sizə qısa sorğu göndəriləcək")
        XCTAssertNil(unknown.position)

        for (raw, event) in [("assigned_to_team", MessageContent.SystemEvent.assignedToTeam),
                             ("conversation_reopened", .conversationReopened)] {
            XCTAssertEqual(MessageContent(type: "system", json: ["event": .string(raw), "text": "x"]).system?.event, event)
        }
    }

    func testCards() throws {
        let card = try XCTUnwrap(try Fixtures.message("26-card.json").content.cards)
        XCTAssertEqual(card.count, 1)
        XCTAssertEqual(card[0].title, "Velosiped icarəsi")
        XCTAssertEqual(card[0].subtitle, "30 dəq, 1 AZN")
        XCTAssertEqual(card[0].imageUrl?.absoluteString, "https://app.clomni.ai/f/velo.jpg")
        XCTAssertEqual(card[0].buttons.map(\.payload), ["node:V1", nil])
        XCTAssertEqual(card[0].buttons.map(\.url?.absoluteString), [nil, "https://example.com"])

        let carousel = try XCTUnwrap(try Fixtures.message("27-carousel.json").content.cards)
        XCTAssertEqual(carousel.map(\.title), ["Tarif 1", "Tarif 2", "Tarif 3"])
        XCTAssertNil(carousel[0].imageUrl)
    }

    func testRating() throws {
        guard case .rating(let rating) = try Fixtures.message("28-rating.json").content else { return XCTFail() }
        XCTAssertEqual(rating.text, "Xidmətimizi qiymətləndirin")
        XCTAssertEqual(rating.scale, .emoji5)
        XCTAssertEqual(rating.comment, .optional)
        XCTAssertNil(rating.submitted)
    }

    func testUnknownTypeKeepsItsContentAndFallback() throws {
        let message = try Fixtures.message("29-unknown-type.json")
        let raw = try Fixtures.json("29-unknown-type.json")
        XCTAssertEqual(message.type, "poll")
        XCTAssertEqual(message.content, .unknown(type: "poll", raw: try XCTUnwrap(raw["content"])))
        XCTAssertEqual(message.fallbackText, "Hansı saat uyğundur? 10:00 / 14:00")
        XCTAssertEqual(message.flow?.interactive, true)
        XCTAssertTrue(log.contains("msg_f29: unknown type \"poll\""), "\(log.lines)")
    }

    func testUnknownFieldsAreSkipped() throws {
        let message = try Fixtures.message("30-unknown-fields.json")
        XCTAssertEqual(message.content, .text("Yeni sahələr nəzərə alınmır"))
        XCTAssertTrue(log.lines.isEmpty, "\(log.lines)")
    }

    func testOperatorWithoutAvatarAndOtherLanguage() throws {
        XCTAssertEqual(try Fixtures.message("31-operator-no-avatar.json").sender, Sender(type: .operator, name: "Leyla"))
        let russian = try Fixtures.message("32-other-language-ru.json")
        XCTAssertEqual(russian.lang, "ru")
        XCTAssertEqual(russian.content, .text("Здравствуйте! Чем можем помочь?"))
    }

    func testBriefLanguageSelectWithoutClientIdOrMeta() throws {
        let message = try Fixtures.message("s5-language-select.json", in: "examples/brief")
        XCTAssertNil(message.clientId)
        XCTAssertEqual(message.content.quickReplies?.buttons.map(\.id), ["b1", "b2", "b3"])
    }
}
