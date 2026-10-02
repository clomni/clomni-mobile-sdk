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
}

final class ChatPresenterTests: XCTestCase {
    /// 2026-10-01T10:32:00Z.
    private let now = Date(timeIntervalSince1970: 1_790_850_720)
    private let utc = TimeZone(identifier: "UTC")!

    private func screen(_ messages: [Message], _ build: (inout ChatSnapshot) -> Void = { _ in }) -> ChatScreen {
        var snapshot = ChatSnapshot(config: Fixture.aparConfig, conversation: Fixture.conversation(status: "bot"),
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
        XCTAssertNil(list[0].meta)
        XCTAssertEqual(list[1].meta, "Clomni · Bot · indi")
        XCTAssertEqual(list[1].avatar, ChatAvatar(url: URL(string: "https://app.clomni.ai/a/bot.png"), initial: "C", isBot: true))
        XCTAssertEqual(list.map(\.side), [.incoming, .incoming, .incoming])
        XCTAssertEqual(list[0].accessibilityLabel, "Clomni bot, 10:30: Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz.")
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
        XCTAssertEqual(reply?.meta, "Leyla · 2 dəq")
        XCTAssertEqual(reply?.avatar?.initial, "L")
        guard case .text(let runs)? = reply?.body else { return XCTFail() }
        XCTAssertEqual(runs.first, TextRun("Gedişinizi yoxladıq.", bold: true))
        XCTAssertEqual(runs.last?.link?.absoluteString, "https://apar.az/sertler")
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
        XCTAssertNil(bubbles(screen([mine, answer])).first?.status)
        XCTAssertNil(bubbles(screen([mine, answer])).last?.status, "nor under the bot's")
        XCTAssertEqual(bubbles(screen([mine])).last?.side, .outgoing)
        XCTAssertNil(bubbles(screen([mine])).last?.avatar)
        XCTAssertNil(bubbles(screen([mine])).last?.meta)
    }

    func testPendingMessages() {
        let mine = Fixture.message("03-text-user.json")
        let sending = PendingMessage(conversationId: "conv_5521", message: ClientMessage(content: .text("Hələ yoldadır")),
                                     preview: "Hələ yoldadır", createdAt: now)
        let list = bubbles(screen([mine]) { $0.pending = [sending] })
        XCTAssertNil(list[0].status, "only the last message has a status")
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
        XCTAssertEqual(bot.lead, .team(Fixture.aparConfig.team.avatars))
        XCTAssertEqual(bot.title, "Apar")
        XCTAssertEqual(bot.subtitle, "Komanda da kömək edə bilər", "the config's header_subtitle, as it came")
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
        XCTAssertEqual(open.subtitle, "Apar · onlayn")

        let away: JSONValue = ["name": "Leyla", "online": false]
        XCTAssertEqual(screen([]) { $0.conversation = Fixture.conversation(status: "open", assignee: away) }.header.subtitle,
                       "Apar")

        let closedHours = ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Apar","primary_color":"#1F9D63"},"team":{"office_hours":{"open_now":false},"reply_time":"Tez"}}
            """##.utf8))
        let afterHours = screen([]) {
            $0.config = closedHours
            $0.conversation = Fixture.conversation(status: "queued")
        }.header
        XCTAssertEqual(afterHours.subtitle, "Hazırda iş saatı deyil", "no next_open_at: just that it is closed")
        XCTAssertEqual(afterHours.lead, .team([]))

        let nextOpen = ProtocolJSON.parseConfig(Data(##"""
            {"brand":{"name":"Apar","primary_color":"#1F9D63"},
             "team":{"office_hours":{"open_now":false,"next_open_at":"2026-10-02T05:00:00Z"}}}
            """##.utf8))
        let untilMorning = screen([]) { $0.config = nextOpen }.header
        XCTAssertEqual(untilMorning.subtitle, "Növbəti iş saatı: sabah 05:00", "local time; these tests run in UTC")
    }

    func testQuickReplies() throws {
        let languages = Fixture.message("07-language-select.json")
        let open = screen([languages]) { $0.answerable = [languages.id] }
        guard case .replies(let block)? = open.items.last else { return XCTFail("\(open.items)") }
        XCTAssertEqual(block.buttons.map(\.title), ["🇦🇿 Azərbaycan dili", "🇬🇧 English", "🇷🇺 Русский"])
        XCTAssertEqual(block.buttons.map(\.id), ["az", "en", "ru"])
        // VoiceOver says "Button" itself, in the system's language (iOS has no Azerbaijani).
        XCTAssertEqual(block.buttons[0].accessibilityLabel, "Azərbaycan dili, 1-ci, cəmi 3")
        XCTAssertEqual(block.layout, .vertical)
        XCTAssertNil(block.back)
        XCTAssertEqual(open.composer.mode, .open)
        XCTAssertTrue(text(bubbles(open).first)?.hasPrefix("Salam, Clomni-yə") == true)

        // Answered (fixture 08): the buttons are gone, the text stays.
        let answered = screen([Fixture.message("08-language-select-answered.json")])
        XCTAssertFalse(answered.items.contains { if case .replies = $0 { return true }; return false })
        XCTAssertEqual(bubbles(answered).count, 1)

        // Apar S: chips, the back button, the composer locked.
        let step = Fixture.message("10-apar-level2-S-chips.json")
        let chips = screen([step]) { $0.answerable = [step.id] }
        guard case .replies(let chipsBlock)? = chips.items.last else { return XCTFail() }
        XCTAssertEqual(chipsBlock.layout, .chips)
        XCTAssertEqual(chipsBlock.back, ReplyButton(id: "back", title: "← Geri", accessibilityLabel: "Geri"))
        XCTAssertEqual(chips.composer.mode, .locked("Yuxarıdakı variantlardan birini seçin"))

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
        let bareScreen = screen([bare]) { $0.answerable = [bare.id] }
        XCTAssertTrue(bubbles(bareScreen).isEmpty, "no text, no bubble")
        XCTAssertEqual(bareScreen.composer.mode, .open, "input_disabled false")
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

        // card, carousel and rating are phase 2: a 1.0 SDK shows their fallback text, like an unknown type.
        for (file, fallback) in [("26-card.json", "Velosiped icarəsi: 30 dəq, 1 AZN. Ətraflı: https://apar.az"),
                                 ("27-carousel.json", "Tarif 1 / Tarif 2 / Tarif 3"),
                                 ("28-rating.json", "Xidmətimizi 1-5 qiymətləndirin"),
                                 ("29-unknown-type.json", "Hansı saat uyğundur? 10:00 / 14:00")] {
            let bubble = bubbles(screen([Fixture.message(file)])).first
            XCTAssertEqual(text(bubble), fallback, file)
            XCTAssertEqual(bubble?.side, .incoming, file)
        }
    }

    func testComposer() {
        let open = screen([]).composer
        XCTAssertEqual(open.mode, .open)
        XCTAssertEqual(open.placeholder, "Mesaj yazın…")
        XCTAssertTrue(open.showsAttach && open.showsEmoji)
        XCTAssertEqual(open.limit, 4_000)
        XCTAssertEqual(open.sendLabel, "Göndər")
        XCTAssertEqual([open.attachLabel, open.imageLabel, open.fileLabel, open.emojiLabel],
                       ["Fayl əlavə et", "Şəkil", "Fayl", "Emoji"])
        let closed = screen([]) { $0.conversation = Fixture.conversation(status: "closed") }.composer
        XCTAssertEqual(closed.mode, .closed(text: "Söhbət bağlanıb", action: "Yeni söhbət başlat"))
        let minimal = screen([]) { $0.config = Fixture.minimalConfig }.composer
        XCTAssertEqual(minimal.placeholder, "Mesaj yazın…", "the SDK's own text")
        XCTAssertTrue(ChatPresenter.canSend(" Salam ", limit: 10))
        XCTAssertFalse(ChatPresenter.canSend(" \n ", limit: 10))
        XCTAssertFalse(ChatPresenter.canSend("12345678901", limit: 10))
    }

    func testTypingStatesAndAnnouncement() {
        let operatorTyping = screen([Fixture.message("01-text-bot.json")]) {
            $0.typing = Sender(type: .operator, name: "Leyla")
        }
        guard case .typing(let line)? = operatorTyping.items.last else { return XCTFail() }
        XCTAssertEqual(line.accessibilityLabel, "Leyla yazır")
        XCTAssertEqual(line.avatar.initial, "L")
        XCTAssertEqual(operatorTyping.announcement,
                       Announcement(id: "msg_f01", text: "Clomni bot, 10:30: Salam! Siz Apar-ın dəstək bölməsi ilə əlaqəyə keçmisiniz."))
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
        XCTAssertEqual(failed.offline, "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq")
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
}
