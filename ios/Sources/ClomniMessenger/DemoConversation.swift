#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

extension Clomni {
    /// Debug builds, for UI tests (ios/Example's ClomniExampleUITests): the conversation screen over a fixed, long
    /// conversation that ends in a form, presented the way the messenger is (a page sheet, its navigation, a hosting
    /// controller), with no server and no `initialize`. Not part of the SDK's API.
    @_spi(ClomniUITesting) @MainActor
    public static func presentDemoConversation() {
        guard let top = UIKitMessenger.topViewController() else {
            return ClomniLog.error("no window to present the demo conversation from")
        }
        let navigation = UIKitMessenger.sheet()
        // `-ClomniDemoFullScreen`: as an app's own full-screen presentation shows it, rather than the page sheet.
        if ProcessInfo.processInfo.arguments.contains("-ClomniDemoFullScreen") { navigation.modalPresentationStyle = .fullScreen }
        let model = ChatModel(controller: ChatController(source: DemoChat(), conversationId: DemoChat.conversationId,
                                                         language: "az"))
        let screen = ChatView(model: model,
                              back: { [weak navigation] in navigation?.dismiss(animated: true) },
                              close: { [weak navigation] in navigation?.dismiss(animated: true) })
        navigation.setViewControllers([UIKitMessenger.host(ScreenRoot(model: MessengerRootModel(), content: screen))],
                                      animated: false)
        top.present(navigation, animated: true)
    }

    /// Debug builds, for UI tests: Home over the previews' example company, in the messenger's page sheet, with no
    /// server. ✕ closes it; the whole screen is one container, "clomni.home", to measure from.
    @_spi(ClomniUITesting) @MainActor
    public static func presentDemoHome() {
        guard let top = UIKitMessenger.topViewController() else {
            return ClomniLog.error("no window to present the demo Home from")
        }
        let navigation = UIKitMessenger.sheet()
        let home = HomeView(screen: PreviewData.presenter.home(PreviewData.snapshot()), theme: PreviewData.theme(dark: false),
                            actions: MessengerActions(close: { [weak navigation] in navigation?.dismiss(animated: true) }))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clomni.home")
        navigation.setViewControllers([UIKitMessenger.host(ScreenRoot(model: MessengerRootModel(), content: home))],
                                      animated: false)
        top.present(navigation, animated: true)
    }

    /// Debug builds, for UI tests: the launcher as `initialize` and `setLauncherVisible(true)` bring it up, the
    /// messenger's own coordinator and renderer over a session that is logged in with a kept look (no server). Called
    /// as early as an app calls `initialize`, before the app's scene and window are up (CM-087), it shows once they
    /// are. A tap opens Home.
    @_spi(ClomniUITesting) @MainActor
    public static func startDemoLauncher() {
        let coordinator = MessengerCoordinator(session: DemoSession(), language: "az")
        let messenger = UIKitMessenger(engine: ClomniEngine(appId: "app_demo", apiKey: "ios_demo"), coordinator: coordinator)
        coordinator.onChange = { [weak messenger] in messenger?.render() }
        coordinator.setLauncherVisible(true)
        DemoSession.kept = (coordinator, messenger)
        Task { await coordinator.start() }
    }
}

/// The demo launcher's SDK: logged in, its look kept from last time, nothing on the network.
actor DemoSession: MessengerSession {
    /// The demo launcher's coordinator and renderer, alive for the app's life (the renderer holds the coordinator
    /// weakly, as the runtime keeps both).
    @MainActor static var kept: (MessengerCoordinator, UIKitMessenger)?

    var isLoggedIn: Bool { true }
    var isAppDisabled: Bool { false }
    var unreadTotal: Int { 2 }
    var config: MessengerConfig? { DemoChat.demoConfig }
    nonisolated func cachedConfigFromDisk() -> MessengerConfig? { DemoChat.demoConfig }
    func loginUnidentifiedUser() async throws {}
    func refreshConfig(language: String?) async -> MessengerConfig? { DemoChat.demoConfig }
    func connect() async {}
    func draftConversation(openedFrom: String?) async -> String { DemoChat.conversationId }
    func startFlow(_ event: String, data: [String: JSONValue], openMessenger: Bool,
                   openedFrom: String?) async throws -> Conversation? { nil }
    func messages(in conversationId: String) async -> [Message] { [] }
    func conversationExists(_ id: String) async -> Bool? { true }
    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) async -> UUID { UUID() }
}

extension DemoChat {
    /// Picks the demo's picture in the open conversation (`stagedPicture`).
    static let stageFile = Notification.Name("ClomniDemoStageFile")

    /// A picture, as the photo library would hand it over: a few pixels of sand colour.
    @MainActor
    static func stagedPicture() -> StagedFile? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90)).image { context in
            UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        }
        return ImagePreparation.staged(image)
    }
}

/// The demo conversation, in memory: 43 messages back and forth, short and long, two pictures (the user's read up to
/// the last one), then a form to fill. It opens the way a phone opens a long conversation: what the cache kept at
/// once, the older history from "the server" in two pages above it, 0.8 s apart. What the user sends is there at
/// once, with one ✓; a question (a text ending in "?") gets an answer ten seconds later, which is what brings up
/// "Yeni mesaj ↓" when the user has scrolled up meanwhile.
///
/// With `-ClomniDemoFlow` it ends in a flow's choices instead of the form, and each choice is answered a second later
/// by the next step: its text and three choices, numbered (TestFlight 13: after a choice the list went to its top).
actor DemoChat: ChatDataSource {
    static let conversationId = "conv_demo"
    private static let flow = ProcessInfo.processInfo.arguments.contains("-ClomniDemoFlow")

    static let demoConfig = ProtocolJSON.parseConfig(Data(#"""
    {"version":1,"brand":{"name":"Clomni","primary_color":"#1A2EB8","header_style":"gradient","glow":false},
     "theme":{"mode":"system","launcher":{"enabled":false}},"home":{"cards":["send","recent"]},
     "team":{"show":true,"avatars":[],"reply_time":"Adətən bir neçə dəqiqəyə cavab veririk"},
     "bot":{"name":"Clomni"},"composer":{},"languages":["az"],"strings":{},"limits":{},"powered_by":true}
    """#.utf8))

    private var stored: [Message]
    /// The history the cache did not keep, the page just before it first.
    private var unloaded: [[Message]]
    private var answerable: Set<String> = []
    private var readUpTo = 0
    private var step = 1
    private var observers: [UUID: @Sendable (ClomniChange) -> Void] = [:]

    init() {
        let form: JSONValue = .object([
            "text": "Sizə geri dönə bilməyimiz üçün məlumatlarınızı qeyd edin.",
            "form_id": "frm_contact",
            "fields": .array([
                .object(["key": "name", "type": "text", "label": "Ad, soyad", "required": .bool(true)]),
                .object(["key": "phone", "type": "phone", "label": "Telefon", "required": .bool(true),
                         "default_country": "AZ"]),
                .object(["key": "email", "type": "email", "label": "Email", "required": .bool(false)]),
            ]),
            "submit_title": "Göndər",
        ])
        // Two weeks back, one week back (the pages "the server" sends), yesterday and today (the cache): many screens,
        // so the list opens far from its first message and the user can read well away from the end (H2).
        let oldest: [Line] = [
            .text("user", "Salam, kartla ödəniş keçmir"),
            .text("operator", "Salam! Hansı kartdır, xəta nə yazır?"),
            .text("user", "Visa. \"Əməliyyat rədd edildi\" yazır, amma kartda pul var. Banka zəng etmişəm, deyirlər ki, "
                  + "onların tərəfində hər şey qaydasındadır və problem sizdədir."),
            .text("operator", "Bir dəqiqə, yoxlayıram."),
            .text("operator", "Ödəniş bankın 3D Secure təsdiqini gözləyir. SMS kodunu yazdıqdan sonra səhifəni bağlamayın, "
                  + "təsdiq bir neçə saniyə çəkə bilər. SMS gəlmirsə, bankın tətbiqində internet ödənişlərinin açıq "
                  + "olduğunu yoxlayın."),
            .text("user", "SMS gəlmir"),
            .image("user", Self.greyPicture, width: 1170, height: 2532, caption: "Ekranda bu çıxır"),
            .text("operator", "Aydındır. Bankın tətbiqində internet ödənişlərini açmaq lazımdır."),
            .text("user", "Tapdım, açdım"),
            .text("user", "İndi keçdi!"),
            .text("operator", "Əla! Başqa sualınız var?"),
            .text("user", "Yox, sağ olun"),
            .text("operator", "Xoş gün!"),
        ]
        let older: [Line] = [
            .text("user", "Salam, aldığım ayaqqabı ölçümə uyğun gəlmədi. Dəyişmək olar?"),
            .text("operator", "Salam! Olar. Qutusu və çeki varsa, 14 gün ərzində dəyişirik."),
            .text("user", "Qutusu var, çek e-poçtdadır"),
            .text("operator", "Sifariş nömrəsini və lazım olan ölçünü yazın."),
            .text("user", "R-0874, 42 ölçü"),
            .image("operator", Self.sandPicture, width: 1280, height: 960,
                   caption: "Bu modelin 42 ölçüsü anbarda var. Kuryer köhnəni götürəndə yenisini gətirəcək."),
            .text("user", "Super. Nə vaxt gələ bilər?"),
            .text("operator", "Sabah 10:00 ilə 14:00 arası. Kuryer gəlməmişdən əvvəl zəng edəcək."),
            .text("user", "Sabah işdəyəm, ünvanı dəyişmək olar? Nizami küçəsi 25, ofis binası, 3-cü mərtəbə. Qəbulda "
                  + "Aysel üçün olduğunu desinlər, mənə xəbər verəcəklər."),
            .text("operator", "Ünvanı dəyişdim, kuryerə də qeyd yazdım."),
            .text("user", "Təşəkkür edirəm"),
            .text("user", "👍"),
            .text("operator", "Buyurun!"),
        ]
        let yesterday: [Line] = [
            .text("user", "Salam, ötən həftəki sifarişim haqqında sualım var"),
            .text("operator", "Salam! Əlbəttə, sifariş nömrəsini yazın, baxım."),
            .text("user", "R-0981"),
            .text("operator", "Bu sifariş 2 oktyabrda çatdırılıb. Nəsə problem olub?"),
            .text("user", "Yox, sadəcə qəbz lazım idi"),
            .text("operator", "Qəbzi e-poçtunuza göndərdim. Spam qovluğuna da baxın."),
            .text("user", "Gəldi, təşəkkürlər"),
            .text("operator", "Buyurun, xoş gün!"),
        ]
        let today: [Line] = [
            .text("bot", "Salam! Clomni-yə xoş gəlmisiniz. Sizə necə kömək edə bilərik?"),
            .text("user", "Salam"),
            .text("user", "As"),
            .text("operator", "Salam, mən Leylayam. Sifarişinizi yoxlayıram, bir dəqiqə."),
            .text("user", "Sifariş nömrəm 1042-dir. Dünən vermişdim, hələ gəlməyib."),
            .text("operator", "**Yoxladım.** Kuryer bu gün saat 18:00-a qədər çatdıracaq."),
            .text("user", "Çox sağ olun 🙏"),
            .text("operator", "Buyurun. Başqa sualınız olsa, yazın."),
        ]
        var seq = 0
        func messages(_ lines: [Line], minutesAgo start: Double) -> [Message] {
            lines.enumerated().compactMap { index, line in
                seq += 1
                return line.message(seq, minutesAgo: start - Double(index))
            }
        }
        let pages = [messages(oldest, minutesAgo: 20_000), messages(older, minutesAgo: 10_000)]
        var cached = messages(yesterday, minutesAgo: 1_500) + messages(today, minutesAgo: 30)
        // A flow's step: only an interactive one can be filled in (ChatController asks canAnswer for those).
        seq += 1
        let last = Self.flow ? Self.choices(seq, step: 1, minutesAgo: 22)
            : Self.message(seq, from: "bot", type: "form", content: form, fallback: "Ad, telefon və email yazın",
                           minutesAgo: 22, interactive: true)
        if let last { cached.append(last) }
        stored = cached
        unloaded = pages.reversed()
        answerable = ["msg_demo_\(seq)"]
        readUpTo = seq - 2
    }

    /// A line of the demo's history.
    private enum Line {
        case text(String, String)
        case image(String, String, width: Int, height: Int, caption: String)

        func message(_ seq: Int, minutesAgo: Double) -> Message? {
            switch self {
            case .text(let sender, let text):
                return DemoChat.text(seq, from: sender, text, minutesAgo: minutesAgo)
            case .image(let sender, let url, let width, let height, let caption):
                let content: JSONValue = .object(["url": .string(url), "thumb_url": .string(url),
                                                  "width": .number(Double(width)), "height": .number(Double(height)),
                                                  "caption": .string(caption)])
                return DemoChat.message(seq, from: sender, type: "image", content: content, fallback: "Şəkil: \(caption)",
                                        minutesAgo: minutesAgo)
            }
        }
    }

    /// Pictures that are there at once, offline: a few pixels of one colour, drawn at the message's size.
    private static let greyPicture = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEUlEQVR4nGOYtWwHHDHg5AAAy34Xof7627gAAAAASUVORK5CYII="
    private static let sandPicture = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGM4uakfjhhwcgDgEhh5OBSDDAAAAABJRU5ErkJggg=="

    /// A flow's step with three choices, numbered by the step: "Velosiped dayandı 2".
    private static func choices(_ seq: Int, step: Int, minutesAgo: Double) -> Message? {
        let titles = ["Velosiped dayandı", "Gedişi bitirə bilmirəm", "Operatorla danış"].map { "\($0) \(step)" }
        let buttons: [JSONValue] = titles.enumerated().map { index, title in
            .object(["id": .string("o_\(step)_\(index)"), "title": .string(title), "payload": .string("node:\(index)")])
        }
        let text = "Nə baş verib? (\(step))"
        return message(seq, from: "bot", type: "quick_replies",
                       content: .object(["text": .string(text), "buttons": .array(buttons)]),
                       fallback: text, minutesAgo: minutesAgo, interactive: true)
    }

    private static func text(_ seq: Int, from sender: String, _ text: String, minutesAgo: Double) -> Message? {
        message(seq, from: sender, type: "text", content: .object(["text": .string(text)]), fallback: text,
                minutesAgo: minutesAgo)
    }

    private static func message(_ seq: Int, from sender: String, type: String, content: JSONValue, fallback: String,
                                minutesAgo: Double, interactive: Bool = false) -> Message? {
        var who: [String: JSONValue] = ["type": .string(sender)]
        if sender == "operator" { who["name"] = "Leyla" }
        if sender == "bot" { who["name"] = "Clomni" }
        var fields: [String: JSONValue] = [
            "id": .string("msg_demo_\(seq)"), "conversation_id": .string(conversationId), "type": .string(type),
            "sender": .object(who), "seq": .number(Double(seq)), "lang": "az", "content": content,
            "created_at": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60))),
            "fallback_text": .string(fallback),
        ]
        if sender == "user" { fields["client_id"] = .string("cm_demo_\(seq)") }
        if interactive {
            fields["flow"] = .object(["flow_id": "flw_demo", "node_id": "F", "interactive": .bool(true)])
        }
        return ProtocolJSON.parseMessage(.object(fields))
    }

    private func append(_ text: String, from sender: String) {
        if let message = Self.text((stored.last?.seq ?? 0) + 1, from: sender, text, minutesAgo: 0) {
            stored.append(message)
        }
        notify()
    }

    /// The next page of history, above what is there.
    private func prependPage() {
        guard !unloaded.isEmpty else { return }
        stored.insert(contentsOf: unloaded.removeFirst(), at: 0)
    }

    private func notify() {
        for observer in observers.values { observer(.messages(conversationId: Self.conversationId)) }
    }

    var config: MessengerConfig? { Self.demoConfig }
    var isLive: Bool { true }
    func conversation(_ id: String) -> Conversation? { nil }
    func refreshConversation(_ id: String) async throws {}
    func messages(in conversationId: String) -> [Message] { stored }
    func pending(in conversationId: String) -> [PendingMessage] { [] }
    func canAnswer(_ message: Message) -> Bool { answerable.contains(message.id) }
    /// The operator has read everything up to "Çox sağ olun": ✓✓ there, one ✓ after it.
    func readByOperator(in conversationId: String) -> Int? { readUpTo }
    func localFile(of pending: PendingMessage) -> URL? { nil }
    /// The first page 0.8 s after the cache, the second (with the first message) 0.8 s after that. A UI test that
    /// watches the history come holds it back until it looks: `-ClomniDemoHistoryAt <seconds since 1970>`.
    func loadMessages(in conversationId: String) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        let at = arguments.firstIndex(of: "-ClomniDemoHistoryAt").flatMap { index in
            arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) : nil
        } ?? 0
        let wait = max(0.8, at - Date().timeIntervalSince1970)
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        prependPage()
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.prependPage()
            self.notify()
        }
    }
    func loadOlder(in conversationId: String) async throws -> Bool { false }
    func markRead(in conversationId: String) {}
    func setTyping(_ isTyping: Bool, in conversationId: String) {}

    func sendText(_ text: String, in conversationId: String, replyTo: String?) -> PendingMessage {
        append(text, from: "user")
        // "Şəkil göndərirəm" picks a picture five seconds later, as if from the photo library: the UI tests read above
        // meanwhile.
        if text == "Şəkil göndərirəm" {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { NotificationCenter.default.post(name: Self.stageFile, object: nil) }
            }
        }
        if text.hasSuffix("?") {
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self.append("Bəli, yoxlayıb sizə yazacağam.", from: "operator")
            }
        }
        return PendingMessage(text: text, in: conversationId)
    }

    func reply(to message: Message, with button: MessageContent.Button) throws -> PendingMessage {
        guard Self.flow else { throw ClomniError.rejected("demo") }
        answerable.remove(message.id)
        append(button.title, from: "user")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.nextStep()
        }
        return PendingMessage(text: button.title, in: message.conversationId)
    }

    private func nextStep() {
        step += 1
        if let next = Self.choices((stored.last?.seq ?? 0) + 1, step: step, minutesAgo: 0) {
            stored.append(next)
            answerable.insert(next.id)
        }
        notify()
    }

    func goBack(from message: Message) throws -> PendingMessage {
        throw ClomniError.rejected("demo")
    }

    func submitForm(_ message: Message, values: [String: JSONValue]) -> PendingMessage {
        answerable.remove(message.id)
        notify()
        return PendingMessage(text: "", in: message.conversationId)
    }

    func submitRating(_ message: Message, score: Int, comment: String?) throws -> PendingMessage {
        throw ClomniError.rejected("demo")
    }

    func sendFile(_ data: Data, fileName: String, mime: String, caption: String?, in conversationId: String,
                  replyTo: String?) throws -> PendingMessage {
        throw ClomniError.rejected("demo")
    }

    func retry(_ clientId: String) {}
    func draftConversation(openedFrom: String?) -> String { Self.conversationId }

    func observe(_ handler: @escaping @Sendable (ClomniChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    func stopObserving(_ token: UUID) {
        observers[token] = nil
    }
}
#endif
