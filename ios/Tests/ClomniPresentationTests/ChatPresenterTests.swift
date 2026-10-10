import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore
@testable import ClomniPresentation

extension Fixture {
    /// A fixture message, with fields replaced (`created_at`, `id`, `seq`, `sender` …).
    static func message(_ name: String, _ changes: [String: JSONValue] = [:]) -> Message {
        guard case .object(var fields)? = ProtocolJSON.decode(data(name)) else { fatalError(name) }
        for (key, value) in changes { fields[key] = value }
        guard let message = ProtocolJSON.parseMessage(.object(fields)) else { fatalError(name) }
        return message
    }

    /// A conversation in a given state, for the header.
    static func conversation(status: String, assignee: JSONValue = nil) -> Conversation {
        let json: JSONValue = ["id": "conv_5521", "status": .string(status), "assignee": assignee,
                               "created_at": "2026-10-01T10:00:00Z"]
        return ProtocolJSON.parseConversation(ProtocolJSON.encode(json))!
    }

    /// A bot conversation whose flow waits on buttons, as the server says (conversation.flow).
    static var onAMenu: Conversation {
        var conversation = conversation(status: "bot")
        conversation.flow = .init(active: true, awaiting: "menu", flowId: "flw_1", nodeId: "S")
        return conversation
    }
}

final class ChatPresenterTests: XCTestCase {
    /// 2026-10-01T10:32:00Z.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!

    private func screen(_ messages: [Message], _ build: (inout ChatSnapshot) -> Void = { _ in }) -> ChatScreen {
        var snapshot = ChatSnapshot(config: Fixture.exampleConfig, conversation: Fixture.conversation(status: "bot"),
                                    messages: messages)
        snapshot.load = .loaded
        build(&snapshot)
        let strings = ClomniStrings(language: "az", overrides: snapshot.config?.strings ?? [:])
        return ChatPresenter(strings: strings, timeZone: utc, now: now).screen(snapshot)
    }

    private func bubbles(_ screen: ChatScreen) -> [Bubble] {
        screen.items.compactMap { if case .bubble(let bubble) = $0 { return bubble }; return nil }
    }

    private func text(_ bubble: Bubble?) -> String? {
        guard case .text(let runs)? = bubble?.body else { return nil }
        return runs.map(\.text).joined()
    }

    func testABotRunHasOneAvatarAndOneMeta() {
        let first = Fixture.message("01-text-bot.json", ["id": "msg_a", "seq": 1, "created_at": "2026-10-01T10:30:50Z"])
        let second = Fixture.message("01-text-bot.json", ["id": "msg_b", "seq": 2, "created_at": "2026-10-01T10:31:30Z",
                                                          "content": ["text": "İkinci"]])
        let later = Fixture.message("01-text-bot.json", ["id": "msg_c", "seq": 3, "created_at": "2026-10-01T10:32:40Z",
                                                         "content": ["text": "Üçüncü"]])
        let list = bubbles(screen([first, second, later]))
        XCTAssertEqual(list.map(\.position), [.first, .last, .single], "70 s later starts a new run")
        XCTAssertNil(list[0].avatar)
        // The bot speaks as the brand over its run, with no "· Bot" (DESIGN-PASS-3 B2); when, in every bubble (G7).
        XCTAssertEqual(list.map(\.nameLine), ["Example", nil, "Example"])
        XCTAssertEqual(list.map(\.time), ["10:30", "10:31", "10:32"], "the clock, not \"indi\"")
        XCTAssertEqual(list[1].avatar, ChatAvatar(url: Fixture.exampleConfig.brand.logoUrl, initial: "E", isBot: true),
                       "the bot is the company: its logo")
        XCTAssertEqual(list.map(\.side), [.incoming, .incoming, .incoming])
        XCTAssertEqual(list[0].accessibilityLabel, "Example bot, 10:30: Salam! Siz Example şirkətinin dəstək bölməsi ilə əlaqəyə keçmisiniz.")
    }

    func testTimeSeparators() {
        let first = Fixture.message("01-text-bot.json", ["created_at": "2026-10-01T08:00:00Z"])
        let near = Fixture.message("03-text-user.json", ["created_at": "2026-10-01T08:59:00Z"])
        let far = Fixture.message("02-text-operator-markdown.json", ["created_at": "2026-10-01T10:30:00Z"])
        let times = screen([first, near, far]).items.compactMap { item -> String? in
            if case .time(_, let text) = item { return text }
            return nil
        }
        XCTAssertEqual(times, ["Bu gün 08:00", "Bu gün 10:30"], "after more than an hour, again")
        guard case .time? = screen([first]).items.first else { return XCTFail("the first message has one") }
    }

    func testOperatorBubbleAndMarkdown() {
        let reply = bubbles(screen([Fixture.message("02-text-operator-markdown.json",
                                                    ["created_at": "2026-10-01T10:30:00Z"])])).first
        XCTAssertEqual(reply?.nameLine, "Leyla")
        XCTAssertEqual(reply?.time, "10:30")
        XCTAssertEqual(reply?.avatar?.initial, "L")
        guard case .text(let runs)? = reply?.body else { return XCTFail() }
        XCTAssertEqual(runs.first, TextRun("Gedişinizi yoxladıq.", bold: true))
        XCTAssertEqual(runs.last?.link?.absoluteString, "https://example.com/sertler")
        XCTAssertEqual(reply?.accessibilityLabel,
                       "Leyla, 10:30: Gedişinizi yoxladıq. Balansınıza 2 AZN qaytarıldı.\nƏtraflı: şərtlər")
    }

    func testStatusOfTheUsersLastMessage() {
        let mine = Fixture.message("03-text-user.json")
        XCTAssertEqual(bubbles(screen([mine])).last?.status?.text, "Göndərildi")
        XCTAssertEqual(bubbles(screen([mine]) { $0.readUpTo = 3 }).last?.status?.text, "Oxundu")
        // VoiceOver reads the status with the bubble: one element.
        let read = bubbles(screen([mine]) { $0.readUpTo = 3 }).last?.accessibilityLabel
        XCTAssertTrue(read?.hasPrefix("Siz, ") == true && read?.hasSuffix(". Oxundu") == true, read ?? "")
        XCTAssertEqual(bubbles(screen([mine]) { $0.readUpTo = 2 }).last?.status?.text, "Göndərildi")
        // A bot message after it: no status under the user's.
        let answer = Fixture.message("01-text-bot.json", ["seq": 4, "created_at": "2026-10-01T10:36:00Z"])
        XCTAssertEqual(bubbles(screen([mine, answer])).first?.status?.mark, .sent, "a bot message after it: still its mark")
        XCTAssertNil(bubbles(screen([mine, answer])).last?.status, "none on the bot's")
        XCTAssertEqual(bubbles(screen([mine])).last?.side, .outgoing)
        XCTAssertNil(bubbles(screen([mine])).last?.avatar)
    }

    /// The user's message is one item from the moment it is written: the server's copy changes only its status, so
    /// the bubble neither flickers nor fades in again.
    func testASentMessageKeepsItsPlaceInTheTranscript() {
        let sending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Gedişim bitmədi")),
                                     preview: "Gedişim bitmədi", createdAt: now)
        let before = bubbles(screen([]) { $0.pending = [sending] }).first
        let confirmed = Fixture.message("03-text-user.json", ["client_id": .string(sending.id)])
        let after = bubbles(screen([confirmed])).first
        XCTAssertEqual(before?.id, sending.id)
        XCTAssertEqual(after?.id, before?.id, "the same key")
        XCTAssertEqual(before?.status?.text, "Göndərilir")
        XCTAssertEqual(after?.status?.text, "Göndərildi")
        let bot = Fixture.message("01-text-bot.json")
        XCTAssertEqual(bubbles(screen([bot])).first?.id, bot.id, "without a client_id, its id")
    }

    func testPendingMessages() {
        let mine = Fixture.message("03-text-user.json")
        let sending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Hələ yoldadır")),
                                     preview: "Hələ yoldadır", createdAt: now)
        let list = bubbles(screen([mine]) { $0.pending = [sending] })
        XCTAssertEqual(list[0].status?.mark, .sent, "every message of the user's has its mark (G7)")
        XCTAssertEqual(text(list[1]), "Hələ yoldadır")
        XCTAssertEqual(list[1].status?.text, "Göndərilir")
        XCTAssertEqual(list.map(\.position), [.first, .last], "the user's messages a minute apart form a run")

        var failed = sending
        failed.state = .failed
        let back = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .back(replyTo: "msg_f10")),
                                  preview: nil, createdAt: now)
        let form = PendingMessage(conversationId: "conv_5521",
                                  message: ClientMessage(content: .formSubmit(replyTo: "msg_f19", formId: "frm_contact",
                                                                              values: [:])),
                                  preview: nil, createdAt: now)
        let withFailure = bubbles(screen([]) { $0.pending = [failed, back, form] })
        XCTAssertEqual(withFailure.count, 2, "a submitted form has no bubble of its own")
        XCTAssertEqual(withFailure[0].status, Bubble.Status(text: "Göndərilmədi · Yenidən cəhd et", isFailure: true,
                                                            retryId: failed.id))
        XCTAssertEqual(withFailure[0].accessibilityLabel, "Siz, 10:32: Hələ yoldadır",
                       "a failure is a button of its own, not part of the bubble")
        XCTAssertEqual(text(withFailure[1]), "← Geri")
        XCTAssertEqual(withFailure[1].status?.text, "Göndərilir")
    }

    /// CM-130: a voice message in its bubble, mine on the right and theirs on the left; quoted and read out by name.
    func testVoiceMessages() {
        let mine = Fixture.message("100-audio-voice-user.json")
        let theirs = Fixture.message("101-audio-operator-no-waveform.json")
        let list = bubbles(screen([mine, theirs]))
        guard case .voice(let voice, _) = list[0].body, case .audio(let audio) = mine.content else { return XCTFail("\(list[0].body)") }
        XCTAssertEqual(voice, VoiceNote(id: mine.id, audio: audio, outgoing: true))
        XCTAssertEqual(list[0].side, .outgoing)
        XCTAssertEqual(list[0].accessibilityLabel, "Siz, 10:31: Səsli mesaj, 0:14. Göndərildi")
        guard case .voice(let operatorVoice, _) = list[1].body else { return XCTFail() }
        XCTAssertFalse(operatorVoice.outgoing)
        XCTAssertNil(operatorVoice.durationMs)
        let quoting = screen([mine]) { $0.replyingTo = mine.id }.composer.quote
        XCTAssertEqual(quoting?.excerpt, "Səsli mesaj")
    }

    /// CM-130: the user's own voice message on its way plays from the kept recording; a spinner only while it uploads.
    func testPendingVoiceMessages() {
        let levels = Array(repeating: 40, count: 64)
        var voice = PendingMessage(conversationId: "conv_5521",
                                   message: ClientMessage(content: .attachment(uploadId: "", caption: nil),
                                                          voice: ClientMessage.Voice(durationMs: 3_200, waveform: levels)),
                                   preview: nil, createdAt: now)
        voice.upload = PendingUpload(fileName: "voice-1.m4a", mime: "audio/mp4", size: 4_000, storedAs: "upload-3")
        let file = URL(fileURLWithPath: "/tmp/upload-3")
        func note(_ build: (inout ChatSnapshot) -> Void) -> VoiceNote? {
            let list = bubbles(screen([]) {
                $0.pending = [voice]
                build(&$0)
            })
            guard case .voice(let note, _) = list.first?.body else { return nil }
            return note
        }
        XCTAssertEqual(note { $0.localFiles = [voice.id: file] },
                       VoiceNote.sending(clientId: voice.id, file: file, durationMs: 3_200, waveform: levels, uploading: true))
        XCTAssertEqual(note { $0.localFiles = [voice.id: file]; $0.isOffline = true }?.sending, false, "waiting: no spinner")
        XCTAssertNil(note { _ in }, "its recording gone: shown as the file it is")
    }

    func testPendingAttachments() {
        var photo = PendingMessage(conversationId: "conv_5521",
                                   message: ClientMessage(content: .attachment(uploadId: "", caption: "Velosiped")),
                                   preview: "Velosiped", createdAt: now)
        photo.upload = PendingUpload(fileName: "velo.jpg", mime: "image/jpeg", size: 1_000, storedAs: "upload-1")
        var pdf = PendingMessage(conversationId: "conv_5521",
                                 message: ClientMessage(content: .attachment(uploadId: "", caption: nil)),
                                 preview: nil, createdAt: now)
        pdf.upload = PendingUpload(fileName: "qaime.pdf", mime: "application/pdf", size: 182_340, storedAs: "upload-2")
        let file = URL(fileURLWithPath: "/tmp/upload-1")
        let list = bubbles(screen([]) {
            $0.pending = [photo, pdf]
            $0.localFiles = [photo.id: file]
        })
        guard case .image(let image) = list[0].body else { return XCTFail("\(list[0].body)") }
        XCTAssertEqual(image.localFile, file)
        XCTAssertEqual(image.caption, [TextRun("Velosiped")])
        guard case .file(let card) = list[1].body else { return XCTFail() }
        XCTAssertEqual(card, Bubble.FileBody(name: "qaime.pdf", size: "182 KB", symbol: "doc.richtext", url: nil))
        XCTAssertEqual(list[1].accessibilityLabel, "Siz, 10:32: qaime.pdf. Göndərilir")
        XCTAssertEqual(list[0].accessibilityHint, "Şəkli tam ekranda açır")
        XCTAssertNil(list[1].accessibilityHint, "not on the server yet: nothing to open")
    }

    func testHeader() {
        let bot = screen([]).header
        let logo = ChatHeader.Lead.brand(ChatAvatar(url: Fixture.exampleConfig.brand.logoUrl, initial: "E", isBot: true))
        XCTAssertEqual(bot.lead, logo, "no operator: the company's logo, never a person's face")
        XCTAssertEqual(bot.title, "Example")
        XCTAssertEqual(bot.subtitle, "Adətən bir neçə dəqiqəyə cavab veririk", "the config's header_subtitle, as it came")
        // Without one in the config, the SDK's own: the server's default, the minutes reply time.
        let plain = screen([]) { $0.config = Fixture.minimalConfig }.header
        XCTAssertEqual(plain.subtitle, "Adətən bir neçə dəqiqəyə cavab veririk")
        XCTAssertEqual(["en", "ru"].map { ClomniStrings(language: $0)[.headerSubtitle] },
                       ["Typically replies in a few minutes", "Обычно отвечаем в течение нескольких минут"])
        XCTAssertEqual(bot.backLabel, "Geri")
        XCTAssertEqual(bot.closeLabel, "Bağla")

        let queued = screen([]) { $0.conversation = Fixture.conversation(status: "queued") }.header
        XCTAssertEqual(queued.subtitle, "Adətən bir neçə dəqiqəyə cavab veririk")

        let leyla: JSONValue = ["name": "Leyla", "avatar_url": "https://app.clomni.ai/a/leyla.png", "online": true]
        let open = screen([]) { $0.conversation = Fixture.conversation(status: "open", assignee: leyla) }.header
        XCTAssertEqual(open.lead, .person(ChatAvatar(url: URL(string: "https://app.clomni.ai/a/leyla.png"), initial: "L",
                                                     isBot: false), online: true))
        XCTAssertEqual(open.title, "Leyla")
        XCTAssertEqual(open.subtitle, "Example", "only the company: online is the dot")

        let away: JSONValue = ["name": "Leyla", "online": false]
        XCTAssertEqual(screen([]) { $0.conversation = Fixture.conversation(status: "open", assignee: away) }.header.subtitle,
                       "Example")

        let closedHours = ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Example","primary_color":"#1F9D63"},"team":{"office_hours":{"open_now":false},"reply_time":"Tez"}}
            """##.utf8))
        let afterHours = screen([]) {
            $0.config = closedHours
            $0.conversation = Fixture.conversation(status: "queued")
        }.header
        XCTAssertEqual(afterHours.subtitle, "Hazırda iş saatı deyil", "no next_open_at: just that it is closed")
        XCTAssertEqual(afterHours.lead, .brand(ChatAvatar(url: nil, initial: "E", isBot: true)))

        let nextOpen = ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Example","primary_color":"#1F9D63"},
             "team":{"office_hours":{"open_now":false,"next_open_at":"2026-10-02T05:00:00Z"}}}
            """##.utf8))
        let untilMorning = screen([]) { $0.config = nextOpen }.header
        XCTAssertEqual(untilMorning.subtitle, "Növbəti iş saatı: sabah 05:00", "local time; these tests run in UTC")
    }

    /// The assignee whatever the status; nobody assigned, the last operator who wrote, with no online dot; else the
    /// company (operator, 2026-10-05).
    func testTheHeaderNamesWhoAnswers() {
        let leyla: JSONValue = ["name": "Leyla", "online": true]
        let queued = screen([]) { $0.conversation = Fixture.conversation(status: "queued", assignee: leyla) }.header
        XCTAssertEqual(queued.title, "Leyla", "the assignee while queued too")

        let wrote = [Fixture.message("02-text-operator-markdown.json", ["id": "m1", "seq": 1]),
                     Fixture.message("01-text-bot.json", ["id": "m2", "seq": 2])]
        let unassigned = screen(wrote) { $0.conversation = Fixture.conversation(status: "queued") }.header
        XCTAssertEqual(unassigned.lead, .person(ChatAvatar(url: URL(string: "https://app.clomni.ai/a/leyla.png"), initial: "L",
                                                           isBot: false), online: false))
        XCTAssertEqual(unassigned.title, "Leyla", "a bot's message after hers changes nothing")
        XCTAssertEqual(unassigned.subtitle, "Example")
        let rauf: JSONValue = ["name": "Rauf", "online": true]
        XCTAssertEqual(screen(wrote) { $0.conversation = Fixture.conversation(status: "open", assignee: rauf) }.header.title,
                       "Rauf", "the assignee before the last writer")
        let logo = ChatHeader.Lead.brand(ChatAvatar(url: Fixture.exampleConfig.brand.logoUrl, initial: "E", isBot: true))
        XCTAssertEqual(screen(Array(wrote.dropFirst())).header.lead, logo, "only the bot wrote: the company")
    }

    /// Operator, 2026-10-04 (72): only the newest bot message's choices, while nothing answered it. Old choices in
    /// the history are never drawn, even when the store would still take an answer for them.
    func testOnlyTheNewestUnansweredChoicesShow() {
        func choices(_ screen: ChatScreen) -> [String] {
            screen.items.compactMap { if case .replies(let block) = $0 { return block.messageId }; return nil }
        }
        let first = Fixture.message("09-example-level1-A.json")
        let second = Fixture.message("10-example-level2-S-chips.json")
        let both = screen([first, second]) { $0.answerable = [first.id, second.id] }
        XCTAssertEqual(choices(both), [second.id], "the older step's choices are history")

        let reply = Fixture.message("03-text-user.json", ["id": "msg_reply", "seq": 10, "created_at": "2026-10-01T10:31:00Z"])
        let answered = screen([first, second, reply]) { $0.answerable = [second.id] }
        XCTAssertEqual(choices(answered), [], "the user answered: only their bubble stays")
        XCTAssertEqual(bubbles(answered).last?.side, .outgoing)

        let sending = screen([first, second]) {
            $0.answerable = [second.id]
            $0.pending = [PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Var")),
                                         preview: "Var", createdAt: Date())]
        }
        XCTAssertEqual(choices(sending), [], "a choice on its way")

        let laterText = Fixture.message("01-text-bot.json", ["id": "msg_later", "seq": 10, "created_at": "2026-10-01T10:31:00Z"])
        XCTAssertEqual(choices(screen([second, laterText]) { $0.answerable = [second.id] }), [],
                       "a newer bot message: the choices are no longer the last word")
        XCTAssertEqual(choices(screen([second])), [], "the store takes no answer: nothing")
    }

    func testQuickReplies() throws {
        let languages = Fixture.message("07-language-select.json")
        let open = screen([languages]) {
            $0.answerable = [languages.id]
            $0.conversation = Fixture.onAMenu
        }
        guard case .replies(let block)? = open.items.last else { return XCTFail("\(open.items)") }
        XCTAssertEqual(block.buttons.map(\.title), ["🇦🇿 Azərbaycan dili", "🇬🇧 English", "🇷🇺 Русский"])
        XCTAssertEqual(block.buttons.map(\.id), ["az", "en", "ru"])
        // VoiceOver says "Button" itself, in the system's language (iOS has no Azerbaijani).
        XCTAssertEqual(block.buttons[0].accessibilityLabel, "Azərbaycan dili, 1-ci, cəmi 3")
        XCTAssertEqual(block.layout, .vertical)
        XCTAssertNil(block.back)
        XCTAssertEqual(open.composer.mode, .hidden, "nothing under a step that waits for a choice")
        XCTAssertTrue(text(bubbles(open).first)?.hasPrefix("Salam, Clomni-yə") == true)

        // Answered (fixture 08): the buttons are gone, the text stays.
        let answered = screen([Fixture.message("08-language-select-answered.json")])
        XCTAssertFalse(answered.items.contains { if case .replies = $0 { return true }; return false })
        XCTAssertEqual(bubbles(answered).count, 1)

        // Example S: chips, the back button, the composer locked.
        let step = Fixture.message("10-example-level2-S-chips.json")
        let chips = screen([step]) {
            $0.answerable = [step.id]
            $0.conversation = Fixture.onAMenu
        }
        guard case .replies(let chipsBlock)? = chips.items.last else { return XCTFail() }
        XCTAssertEqual(chipsBlock.layout, .chips)
        XCTAssertEqual(chipsBlock.back, ReplyButton(id: "back", title: "← Geri", accessibilityLabel: "Geri"))
        XCTAssertEqual(chips.composer.mode, .hidden)

        // 13: the long title whole (the view wraps it to two lines); 14: ten buttons; 15: buttons without text.
        let long = Fixture.message("13-button-title-over-80.json")
        let longScreen = screen([long]) { $0.answerable = [long.id] }
        guard case .replies(let longBlock)? = longScreen.items.last else { return XCTFail() }
        XCTAssertEqual(longBlock.buttons[0].title.count, 112)
        let ten = Fixture.message("14-ten-buttons.json")
        let tenScreen = screen([ten]) { $0.answerable = [ten.id] }
        guard case .replies(let tenBlock)? = tenScreen.items.last else { return XCTFail() }
        XCTAssertEqual(tenBlock.buttons.count, 10)
        XCTAssertEqual(tenBlock.buttons[9].accessibilityLabel, "Variant 10, 10-cu, cəmi 10")
        let bare = Fixture.message("15-quick-replies-no-text.json")
        let bareScreen = screen([bare]) {
            $0.answerable = [bare.id]
            $0.conversation = Fixture.onAMenu
        }
        XCTAssertTrue(bubbles(bareScreen).isEmpty, "no text, no bubble")
        XCTAssertEqual(bareScreen.composer.mode, .hidden, "the flow's menu hides it even with input_disabled false")
    }

    func testTheFlowsOwnRestartButtonLeavesNoSecondBack() {
        let restart = Fixture.message("10-example-level2-S-chips.json", ["content": [
            "text": "Seçin", "allow_back": true,
            "buttons": [["id": "a", "title": "Kart", "payload": "a"], ["id": "r", "title": "↺ Yenidən başla", "payload": "r"]],
        ]])
        guard case .replies(let block)? = screen([restart]) { $0.answerable = [restart.id] }.items.last else {
            return XCTFail()
        }
        XCTAssertEqual(block.buttons.count, 2)
        XCTAssertNil(block.back)
        XCTAssertTrue(ChatPresenter.isRestart("Start over"))
        XCTAssertFalse(ChatPresenter.isRestart("Kart"))
    }

    func testAnOptionalFieldSaysSo() {
        let contact = Fixture.message("19-form-contact.json")
        guard case .form(let card)? = bubbles(screen([contact]) { $0.answerable = [contact.id] }).first?.body else {
            return XCTFail()
        }
        XCTAssertEqual(card.fields.map(\.shownLabel), ["Ad, soyad", "Telefon", "Email (istəyə görə)"])
    }

    func testForms() throws {
        let contact = Fixture.message("19-form-contact.json")
        let live = screen([contact]) {
            $0.answerable = [contact.id]
            $0.known = ["name": "Aysel Məmmədova", "email": "aysel@example.com"]
        }
        guard case .form(let card)? = bubbles(live).first?.body else { return XCTFail() }
        XCTAssertFalse(card.readOnly)
        XCTAssertEqual(card.fields.map(\.id), ["name", "phone", "email"])
        XCTAssertEqual(card.fields.map(\.initialValue), ["Aysel Məmmədova", "", "aysel@example.com"])
        XCTAssertEqual(card.submitTitle, "Göndər")
        XCTAssertEqual(card.fields.map(\.accessibilityLabel), ["Ad, soyad, məcburi", "Telefon, məcburi", "Email"])
        XCTAssertEqual(card.announcement(for: ["email": "Email düzgün deyil"]), "Email: Email düzgün deyil")
        XCTAssertEqual(card.announcement(for: ["email": "Email düzgün deyil", "phone": "Bu sahəni doldurun"]),
                       "Telefon: Bu sahəni doldurun", "the first field on screen")
        XCTAssertNil(card.announcement(for: [:]))
        XCTAssertNil(card.sentLabel)
        XCTAssertEqual(card.text?.first?.text, "Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.")

        guard case .form(let sent)? = bubbles(screen([Fixture.message("21-form-submitted.json")])).first?.body else {
            return XCTFail()
        }
        XCTAssertTrue(sent.readOnly)
        XCTAssertEqual(sent.sentLabel, "Göndərildi")
        XCTAssertEqual(sent.submitted.map(\.value), ["Aysel Məmmədova", "+994501234567", "aysel@example.com"])

        guard case .form(let stale)? = bubbles(screen([contact])).first?.body else { return XCTFail() }
        XCTAssertTrue(stale.readOnly, "no longer the live step")
    }

    func testImagesAndFiles() {
        guard case .image(let image)? = bubbles(screen([Fixture.message("16-image.json")])).first?.body else {
            return XCTFail()
        }
        XCTAssertEqual(image.url?.absoluteString, "https://app.clomni.ai/f/velo_480.jpg", "the thumbnail")
        XCTAssertEqual(image.fullUrl?.absoluteString, "https://app.clomni.ai/f/velo.jpg")
        XCTAssertEqual([image.width, image.height], [220, 165])
        XCTAssertTrue(image.sizeKnown)
        XCTAssertEqual(image.caption, [TextRun("Velosiped Nizami küçəsindədir")])

        let unknown = bubbles(screen([Fixture.message("17-image-no-dimensions.json")])).first
        guard case .image(let placeholder)? = unknown?.body else { return XCTFail() }
        XCTAssertFalse(placeholder.sizeKnown)
        XCTAssertEqual(placeholder.url?.absoluteString, "https://app.clomni.ai/f/receipt.png")
        XCTAssertEqual(unknown?.accessibilityLabel, "Leyla, 10:46: Şəkil")

        let file = bubbles(screen([Fixture.message("18-file-pdf.json")])).first
        guard case .file(let card)? = file?.body else { return XCTFail() }
        XCTAssertEqual(card, Bubble.FileBody(name: "qaime.pdf", size: "182 KB", symbol: "doc.richtext",
                                             url: URL(string: "https://app.clomni.ai/f/qaime.pdf")))
        XCTAssertEqual(file?.accessibilityLabel, "Leyla, 10:47: Fayl: qaime.pdf, 182 KB")
        XCTAssertEqual(file?.accessibilityHint, "Faylı açır")
        XCTAssertEqual(unknown?.accessibilityHint, "Şəkli tam ekranda açır")
        XCTAssertNil(bubbles(screen([Fixture.message("01-text-bot.json")])).first?.accessibilityHint)
    }

    func testSystemLinesAndFallbacks() {
        let leyla: JSONValue = ["name": "Leyla", "avatar_url": "https://app.clomni.ai/a/leyla.png"]
        let system = screen(["22-system-waiting-in-queue.json", "23-system-operator-joined.json",
                             "24-system-conversation-closed.json", "25-system-unknown-event.json"]
            .map { Fixture.message($0) }) { $0.conversation = Fixture.conversation(status: "open", assignee: leyla) }
        let lines = system.items.compactMap { item -> SystemLine? in
            if case .system(let line) = item { return line }
            return nil
        }
        XCTAssertEqual(lines.map(\.text), ["Sizi operatora yönləndiririk", "Leyla söhbətə qoşuldu", "Söhbət bağlanıb",
                                           "Sizə qısa sorğu göndəriləcək"])
        XCTAssertEqual(lines[0].avatars.count, 3, "the team waits with them")
        XCTAssertEqual(lines[1].avatars.first?.initial, "L")
        XCTAssertTrue(lines[2].avatars.isEmpty)
        XCTAssertTrue(bubbles(system).isEmpty)

        // card and carousel are phase 2: a 1.0 SDK shows their fallback text, like an unknown type.
        for (file, fallback) in [("26-card.json", "Velosiped icarəsi: 30 dəq, 1 AZN. Ətraflı: https://example.com"),
                                 ("27-carousel.json", "Tarif 1 / Tarif 2 / Tarif 3"),
                                 ("29-unknown-type.json", "Hansı saat uyğundur? 10:00 / 14:00")] {
            let bubble = bubbles(screen([Fixture.message(file)])).first
            XCTAssertEqual(text(bubble), fallback, file)
            XCTAssertEqual(bubble?.side, .incoming, file)
        }
    }

    /// CM-087 (the RN test on Android): the panel assigns Leyla when she first replies, so the server numbers
    /// "Leyla söhbətə qoşuldu" after her first messages. The line stands before them.
    func testTheOperatorJoinsBeforeHerFirstMessages() {
        func leyla(_ seq: Int, _ at: String, _ text: String) -> Message {
            Fixture.message("02-text-operator-markdown.json", ["id": .string("msg_l\(seq)"), "seq": .number(Double(seq)),
                                                               "created_at": .string(at), "content": ["text": .string(text)]])
        }
        let user = Fixture.message("03-text-user.json", ["id": "msg_u1", "seq": 1, "created_at": "2026-10-01T10:38:00Z"])
        func joined(_ seq: Int, _ at: String) -> Message {
            Fixture.message("23-system-operator-joined.json", ["id": .string("msg_j\(seq)"), "seq": .number(Double(seq)),
                                                               "created_at": .string(at)])
        }
        func order(_ messages: [Message]) -> [String] {
            screen(messages).items.compactMap { item -> String? in
                switch item {
                case .bubble(let bubble): return text(bubble)
                case .system(let line): return line.text
                default: return nil
                }
            }
        }
        XCTAssertEqual(order([user, leyla(2, "2026-10-01T10:40:10Z", "Salam"), leyla(3, "2026-10-01T10:40:30Z", "Baxıram"),
                              joined(4, "2026-10-01T10:40:31Z")]),
                       ["Gedişim bitmədi, pul çıxılmağa davam edir", "Leyla söhbətə qoşuldu", "Salam", "Baxıram"])
        XCTAssertEqual(ChatPresenter.joinedFirst([user, leyla(2, "2026-10-01T10:40:10Z", "Salam"),
                                                  joined(3, "2026-10-01T10:40:31Z")]).map(\.id),
                       ["msg_u1", "msg_j3", "msg_l2"])

        // Where it already stands, it stays: before her messages; after someone else's; when she wrote earlier (she
        // joins again); after messages of hers long before it.
        XCTAssertEqual(ChatPresenter.joinedFirst([user, joined(2, "2026-10-01T10:40:00Z"), leyla(3, "2026-10-01T10:40:10Z", "Salam")])
            .map(\.id), ["msg_u1", "msg_j2", "msg_l3"])
        let rauf = Fixture.message("02-text-operator-markdown.json", ["id": "msg_r2", "seq": 2, "created_at": "2026-10-01T10:40:10Z",
                                                                      "sender": ["type": "operator", "name": "Rauf"]])
        XCTAssertEqual(ChatPresenter.joinedFirst([user, rauf, joined(3, "2026-10-01T10:40:31Z")]).map(\.id),
                       ["msg_u1", "msg_r2", "msg_j3"])
        XCTAssertEqual(ChatPresenter.joinedFirst([leyla(1, "2026-10-01T10:30:00Z", "Əvvəl"), user,
                                                  leyla(3, "2026-10-01T10:40:10Z", "Yenə"), joined(4, "2026-10-01T10:40:31Z")])
            .map(\.id), ["msg_l1", "msg_u1", "msg_l3", "msg_j4"])
        XCTAssertEqual(ChatPresenter.joinedFirst([user, leyla(2, "2026-10-01T10:30:00Z", "Çoxdan"), joined(3, "2026-10-01T10:40:31Z")])
            .map(\.id), ["msg_u1", "msg_l2", "msg_j3"])
    }

    /// CM-087: a rating is a card of its own, open until answered; the answer on its way or sent locks it with the
    /// thanks, a failed one opens it again.
    func testRating() throws {
        let rating = Fixture.message("28-rating.json")
        func card(_ build: (inout ChatSnapshot) -> Void = { _ in }) -> RatingCard? {
            guard case .rating(let card)? = bubbles(screen([rating], build)).first?.body else { return nil }
            return card
        }
        let open = try XCTUnwrap(card { $0.answerable = [rating.id] })
        XCTAssertEqual(open.state, .open)
        XCTAssertEqual(open.text, [TextRun("Xidmətimizi qiymətləndirin")])
        XCTAssertEqual(open.options.map(\.face), ["😞", "😑", "😐", "😀", "😍"])
        XCTAssertEqual(open.options.map(\.accessibilityLabel), ["Çox pis", "Pis", "Normal", "Yaxşı", "Əla"])
        XCTAssertEqual(open.commentField?.shownLabel, "Rəyiniz (istəyə görə)")
        XCTAssertEqual(open.commentField?.type, .textarea)
        XCTAssertEqual(open.submitTitle, "Göndər")
        XCTAssertNil(open.sentAccessibilityLabel)
        let bubble = try XCTUnwrap(bubbles(screen([rating]) { $0.answerable = [rating.id] }).first)
        XCTAssertFalse(bubble.replyable, "answered in its card, not quoted")
        XCTAssertEqual(bubble.accessibilityLabel, "Example bot, 11:02: Xidmətimizi qiymətləndirin")

        let answer = PendingMessage(conversationId: "conv_5521",
                                    message: ClientMessage(content: .ratingSubmit(replyTo: rating.id, score: 5,
                                                                                  comment: "Tez cavab verdiniz")),
                                    preview: nil, createdAt: now)
        let sending = try XCTUnwrap(card { $0.pending = [answer] })
        XCTAssertEqual(sending.state, .sent(score: 5, comment: "Tez cavab verdiniz"), "offline it waits, locked")
        XCTAssertEqual(sending.sentAccessibilityLabel,
                       "Qiymətiniz: Əla. Tez cavab verdiniz. Rəyiniz üçün təşəkkür edirik")
        XCTAssertEqual(bubbles(screen([rating]) { $0.pending = [answer] }).count, 1, "the answer has no bubble")
        var failed = answer
        failed.state = .failed
        XCTAssertEqual(card { $0.pending = [failed] }?.state, .open, "a failure opens it again")
        XCTAssertEqual(card()?.state, .sent(score: nil, comment: nil), "answered elsewhere or closed: nothing lit")

        let fromServer = Fixture.message("28-rating.json", ["content": [
            "text": "Necə idi?", "scale": "star_5", "comment": "none", "submitted": ["score": 4, "comment": ""],
        ]])
        guard case .rating(let stars)? = bubbles(screen([fromServer]) { $0.answerable = [fromServer.id] }).first?.body else {
            return XCTFail()
        }
        XCTAssertEqual(stars.state, .sent(score: 4, comment: nil), "the server's submitted, whatever else says")
        XCTAssertNil(stars.commentField)
        XCTAssertEqual(stars.options.map(\.face), [nil, nil, nil, nil, nil])
        XCTAssertEqual(stars.options[3].accessibilityLabel, "5 ulduzdan 4")
        XCTAssertEqual(stars.sentAccessibilityLabel, "Qiymətiniz: 5 ulduzdan 4. Rəyiniz üçün təşəkkür edirik")

        let required = Fixture.message("28-rating.json", ["content": [
            "text": "?", "scale": "emoji_5", "comment": "required", "submitted": nil,
        ]])
        guard case .rating(let asks)? = bubbles(screen([required])).first?.body else { return XCTFail() }
        XCTAssertEqual(asks.commentField?.shownLabel, "Rəyiniz")
        XCTAssertEqual(asks.commentField?.accessibilityLabel, "Rəyiniz, məcburi")
        XCTAssertEqual(asks.commentField?.required, true)
    }

    /// CM-087: addresses, emails and phones in a message's text are links, the user's own too.
    func testLinksInMessages() throws {
        let bot = Fixture.message("01-text-bot.json", ["content": ["text": "**Yazın:** info@example.com və ya +994501234567"]])
        guard case .text(let runs)? = bubbles(screen([bot])).first?.body else { return XCTFail() }
        XCTAssertEqual(runs.compactMap(\.link?.absoluteString), ["mailto:info@example.com", "tel:+994501234567"])
        XCTAssertEqual(runs.first, TextRun("Yazın:", bold: true))
        let mine = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("www.example.com")),
                                  preview: "www.example.com", createdAt: now)
        guard case .text(let sent)? = bubbles(screen([]) { $0.pending = [mine] }).first?.body else { return XCTFail() }
        XCTAssertEqual(sent, [TextRun("www.example.com", link: URL(string: "https://www.example.com"))])
        XCTAssertEqual(text(bubbles(screen([Fixture.message("26-card.json")])).first),
                       "Velosiped icarəsi: 30 dəq, 1 AZN. Ətraflı: https://example.com")
    }

    func testComposer() {
        let open = screen([]).composer
        XCTAssertEqual(open.mode, .open)
        XCTAssertEqual(open.placeholder, "Mesaj yazın…")
        XCTAssertTrue(open.showsAttach)
        XCTAssertEqual(open.limit, 4_000)
        XCTAssertEqual(open.voiceSeconds, 300, "the recorder's limit, the config's or five minutes")
        XCTAssertEqual(open.sendLabel, "Göndər")
        XCTAssertEqual([open.attachLabel, open.mediaLabel, open.cameraLabel, open.fileLabel, open.removeAttachmentLabel],
                       ["Fayl əlavə et", "Şəkil və ya video", "Kamera", "Fayl", "Sil"])
        let closed = screen([]) { $0.conversation = Fixture.conversation(status: "closed") }.composer
        XCTAssertEqual(closed.mode, .closed(text: "Söhbət bağlanıb", action: "Yeni söhbət başlat"))
        let minimal = screen([]) { $0.config = Fixture.minimalConfig }.composer
        XCTAssertEqual(minimal.placeholder, "Mesaj yazın…", "the SDK's own text")
        XCTAssertTrue(ChatPresenter.canSend(" Salam ", limit: 10))
        XCTAssertFalse(ChatPresenter.canSend(" \n ", limit: 10))
        XCTAssertFalse(ChatPresenter.canSend("12345678901", limit: 10))
    }

    /// Operator, 2026-10-05: the composer goes by conversation.flow alone. While a flow waits for a button, a form or
    /// its next step there is none; for a question answered in words, at its end or on a handover it is back.
    func testTheFlowHoldsTheComposerUntilItWaitsForWords() {
        let statement = Fixture.message("01-text-bot.json")
        func mode(_ flow: Conversation.FlowState?) -> ChatComposer.Mode {
            screen([statement]) { $0.conversation?.flow = flow }.composer.mode
        }
        XCTAssertEqual(mode(.init(active: true, awaiting: "menu")), .hidden)
        XCTAssertEqual(mode(.init(active: true)), .hidden, "between steps")
        XCTAssertEqual(mode(.init(active: true, awaiting: "form")), .hidden)
        XCTAssertEqual(mode(.init(active: true, awaiting: "buttons")), .hidden, "a value this SDK does not know is not text")
        XCTAssertEqual(mode(.init(active: true, awaiting: "text")), .open, "a question answered in words")
        XCTAssertEqual(mode(.init(active: false)), .open, "ended or handed over")
        XCTAssertEqual(mode(nil), .open, "no flow sent (an older server)")
        XCTAssertEqual(screen([statement]) {
            $0.conversation = Fixture.conversation(status: "queued")
            $0.conversation?.flow = .init(active: true, awaiting: "menu")
        }.composer.mode, .hidden, "the field decides, not the status")
        XCTAssertEqual(screen([]) { $0.load = .loading }.composer.mode, .hidden)
    }

    func testTypingStatesAndAnnouncement() {
        let operatorTyping = screen([Fixture.message("01-text-bot.json")]) {
            $0.typing = Sender(type: .operator, name: "Leyla")
        }
        guard case .typing(let line)? = operatorTyping.items.last else { return XCTFail() }
        XCTAssertEqual(line.accessibilityLabel, "Leyla yazır")
        XCTAssertEqual(line.avatar.initial, "L")
        XCTAssertEqual(operatorTyping.announcement,
                       Announcement(id: "msg_f01", text: "Example bot, 10:30: Salam! Siz Example şirkətinin dəstək bölməsi ilə əlaqəyə keçmisiniz."))
        XCTAssertNil(screen([Fixture.message("03-text-user.json")]).announcement, "the user's own message is not news")

        var loading = ChatSnapshot(config: nil)
        let presenter = ChatPresenter(strings: ClomniStrings(language: "az"), timeZone: utc, now: now)
        XCTAssertEqual(presenter.screen(loading).phase, .loading)
        XCTAssertEqual(presenter.screen(loading).loadingLabel, "Yüklənir")
        loading.load = .failed
        loading.isOffline = true
        let failed = presenter.screen(loading)
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.failure?.retry, "Yenidən cəhd et")
        XCTAssertEqual(failed.offline, "İnternet yoxdur")
    }

    /// No words under the user's message: its time and the clock, then ✓; the words are VoiceOver's (operator,
    /// 2026-10-06).
    func testStatusIsAMarkWithTheTime() {
        let sending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Salam")),
                                     preview: "Salam", createdAt: now)
        XCTAssertEqual(bubbles(screen([]) { $0.pending = [sending] }).first?.status,
                       Bubble.Status(text: "Göndərilir", isFailure: false, retryId: nil, mark: .sending))
        let mine = Fixture.message("03-text-user.json", ["created_at": "2026-10-01T10:30:00Z"])
        XCTAssertEqual(bubbles(screen([mine])).first?.status,
                       Bubble.Status(text: "Göndərildi", isFailure: false, retryId: nil, mark: .sent))
        XCTAssertEqual(bubbles(screen([mine])).first?.time, "10:30")
        XCTAssertEqual(bubbles(screen([mine]) { $0.readUpTo = 3 }).first?.status?.mark, .read)
        XCTAssertTrue(bubbles(screen([mine]) { $0.readUpTo = 3 }).first?.accessibilityLabel.hasSuffix(". Oxundu") == true,
                      "VoiceOver still reads it")
        var failed = sending
        failed.state = .failed
        XCTAssertNil(bubbles(screen([]) { $0.pending = [failed] }).first?.status?.mark, "a failure is in words")
    }

    /// The time and the mark are in each bubble (operator, 2026-10-07, G7): the user's run has a mark on every
    /// message, read up to where the operator read; no line of its own under a run.
    func testTheTimeAndMarkAreInEveryBubble() {
        let first = Fixture.message("03-text-user.json", ["id": "msg_u1", "client_id": "cm_u1", "seq": 3, "created_at": "2026-10-01T10:30:00Z"])
        let second = Fixture.message("03-text-user.json", ["id": "msg_u2", "client_id": "cm_u2", "seq": 4, "created_at": "2026-10-01T10:30:40Z",
                                                           "content": ["text": "Bir də bu"]])
        let sending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Üçüncü")),
                                     preview: "Üçüncü", createdAt: now.addingTimeInterval(-60))
        let list = bubbles(screen([first, second]) {
            $0.readUpTo = 3
            $0.pending = [sending]
        })
        XCTAssertEqual(list.map(\.position), [.first, .middle, .last])
        XCTAssertEqual(list.compactMap(\.status?.mark), [.read, .sent, .sending])
        XCTAssertEqual(list.map(\.time), ["10:30", "10:30", "10:31"])
        XCTAssertTrue(list[0].accessibilityLabel.hasSuffix(". Oxundu"), list[0].accessibilityLabel)
    }

    /// The typing row: one avatar, at the end; none while the flow waits for a choice (operator, 2026-10-06).
    func testTypingRowTakesTheAvatarAndWaitsForNoChoice() {
        let bot = Fixture.message("01-text-bot.json", ["created_at": "2026-10-01T10:31:30Z"])
        let botTyping = screen([bot]) { $0.typing = Sender(type: .bot, id: "bot_other") }
        guard case .typing? = botTyping.items.last else { return XCTFail("typing is a row of its own at the end") }
        XCTAssertNil(bubbles(botTyping).first?.avatar, "the bot's run gives its avatar to the typing row")
        XCTAssertEqual(bubbles(botTyping).first?.time, "10:31")
        let leylaTyping = screen([bot]) { $0.typing = Sender(type: .operator, name: "Leyla") }
        XCTAssertNotNil(bubbles(leylaTyping).first?.avatar, "someone else typing: the bot keeps its own")

        let step = Fixture.message("10-example-level2-S-chips.json")
        func typing(_ build: (inout ChatSnapshot) -> Void) -> Bool {
            let items = screen([step]) {
                $0.conversation = Fixture.onAMenu
                $0.answerable = [step.id]
                $0.typing = Sender(type: .bot)
                build(&$0)
            }.items
            return items.contains { if case .typing = $0 { return true }; return false }
        }
        XCTAssertFalse(typing { _ in }, "choices wait: nobody is typing")
        XCTAssertTrue(typing {
            $0.pending = [PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("A")),
                                         preview: "A", createdAt: now)]
        }, "once chosen, the bot may type")
        XCTAssertTrue(typing { $0.conversation = Fixture.conversation(status: "bot") }, "the flow waits for nothing")
        XCTAssertTrue(typing { $0.answerable = [] }, "the choices are not live")
    }

    /// Every message fixture, valid or not, reaches the screen as something: the Linux half of the snapshot tests.
    func testEveryMessageFixtureRenders() throws {
        let index = try JSONDecoder().decode([[String: JSONValue]].self, from: Fixture.data("index.json"))
        var rendered = 0
        for entry in index where entry["schema"]?.stringValue == "message.json" {
            let file = try XCTUnwrap(entry["file"]?.stringValue)
            guard let message = ProtocolJSON.parseMessage(Fixture.data(file)) else { continue }
            let chat = screen([message]) { $0.answerable = message.flow?.interactive == true ? [message.id] : [] }
            XCTAssertFalse(chat.items.filter { if case .time = $0 { return false }; return true }.isEmpty, file)
            rendered += 1
        }
        XCTAssertGreaterThanOrEqual(rendered, 35)
    }

    /// DESIGN-PASS-3 F2: the quote in the bubble, over the field, and who may be answered.
    func testReplies() {
        func quoteOf(_ file: String) -> Bubble.Quote? { bubbles(screen([Fixture.message(file)])).first?.quote }
        XCTAssertEqual(quoteOf("66-reply-user-to-operator.json"), Bubble.Quote(
            messageId: "msg_f65", author: "Leyla",
            excerpt: "Ödənişi kartla etmisiniz, yoxsa balansdan? Qəbzin şəklini də göndərə bilərsiniz, yoxlayaq."))
        XCTAssertEqual(quoteOf("67-reply-operator-to-image.json"),
                       Bubble.Quote(messageId: "msg_f62", author: "Siz", excerpt: "qebz.jpg"), "the user's own is \"Siz\"")
        XCTAssertEqual(quoteOf("68-reply-to-deleted.json"),
                       Bubble.Quote(messageId: "msg_f60", author: "Siz", excerpt: "Mesaj silinib"))
        XCTAssertNil(quoteOf("70-invalid-reply-to-without-kind.json"), "a broken reply_to: the message without its quote")

        // Answering: the quote over the field; the user's message on its way shows it too.
        let fromLeyla = Fixture.message("02-text-operator-markdown.json")
        let answering = screen([fromLeyla]) {
            $0.conversation = Fixture.conversation(status: "open")
            $0.replyingTo = fromLeyla.id
        }
        let quote = answering.composer.quote
        XCTAssertEqual(quote?.messageId, fromLeyla.id)
        XCTAssertEqual(quote?.excerpt.contains("\n"), false, "one line")
        XCTAssertEqual(answering.composer.cancelQuoteLabel, "Bağla")
        XCTAssertEqual([answering.replyLabel, answering.copyLabel], ["Cavabla", "Kopyala"])
        let bubble = bubbles(answering).first
        XCTAssertEqual(bubble?.replyable, true)
        XCTAssertEqual(bubble?.messageId, fromLeyla.id)
        XCTAssertNotNil(bubble?.copyText)
        let sending = screen([fromLeyla]) {
            $0.pending = [PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Bəli"),
                                                                                              replyTo: fromLeyla.id),
                                         preview: "Bəli", createdAt: self.now)]
        }
        let mine = bubbles(sending).last
        XCTAssertEqual(mine?.quote, quote)
        XCTAssertEqual(mine?.replyable, false, "still on its way: nothing to answer yet")
        XCTAssertEqual(mine?.copyText, "Bəli")

        // A flow waiting for a choice: no composer, so nothing is answered; copying still works.
        let menu = screen([fromLeyla]) {
            $0.conversation = Fixture.onAMenu
            $0.replyingTo = fromLeyla.id
        }
        XCTAssertNil(menu.composer.quote)
        XCTAssertEqual(bubbles(menu).first?.replyable, false)
        XCTAssertNotNil(bubbles(menu).first?.copyText)
    }
}
