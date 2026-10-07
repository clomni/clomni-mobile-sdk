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
    /// Debug builds, for UI tests (ios/Example's ClomniExampleUITests): the conversation screen over a fixed
    /// conversation that ends in a form, presented the way the messenger is (a page sheet, its navigation, a hosting
    /// controller), with no server and no `initialize`. Not part of the SDK's API.
    @_spi(ClomniUITesting) @MainActor
    public static func presentDemoConversation() {
        guard let top = UIKitMessenger.topViewController() else {
            return ClomniLog.error("no window to present the demo conversation from")
        }
        let navigation = UIKitMessenger.sheet()
        let model = ChatModel(controller: ChatController(source: DemoChat(), conversationId: DemoChat.conversationId,
                                                         language: "az"))
        let screen = ChatView(model: model,
                              back: { [weak navigation] in navigation?.dismiss(animated: true) },
                              close: { [weak navigation] in navigation?.dismiss(animated: true) })
        navigation.setViewControllers([UIKitMessenger.host(ScreenRoot(model: MessengerRootModel(), content: screen))],
                                      animated: false)
        top.present(navigation, animated: true)
    }
}

/// The demo conversation, in memory: a few messages back and forth (the user's read up to the last one), then a form
/// to fill. What the user sends is there at once, with one ✓; a question (a text ending in "?") gets an answer four
/// seconds later, which is what brings up "Yeni mesaj ↓" when the user has scrolled up meanwhile.
actor DemoChat: ChatDataSource {
    static let conversationId = "conv_demo"

    private static let demoConfig = ProtocolJSON.parseConfig(Data(#"""
    {"version":1,"brand":{"name":"Clomni","primary_color":"#1A2EB8","header_style":"gradient","glow":false},
     "theme":{"mode":"system","launcher":{"enabled":false}},"home":{"cards":["send","recent"]},
     "team":{"show":true,"avatars":[],"reply_time":"Adətən bir neçə dəqiqəyə cavab veririk"},
     "bot":{"name":"Clomni"},"composer":{},"languages":["az"],"strings":{},"limits":{},"powered_by":true}
    """#.utf8))

    private var stored: [Message]
    private var answerable: Set<String> = ["msg_demo_9"]
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
        stored = [
            Self.text(1, from: "bot", "Salam! Clomni-yə xoş gəlmisiniz. Sizə necə kömək edə bilərik?", minutesAgo: 30),
            Self.text(2, from: "user", "Salam", minutesAgo: 29),
            Self.text(3, from: "user", "As", minutesAgo: 29),
            Self.text(4, from: "operator", "Salam, mən Leylayam. Sifarişinizi yoxlayıram, bir dəqiqə.", minutesAgo: 28),
            Self.text(5, from: "user", "Sifariş nömrəm 1042-dir. Dünən vermişdim, hələ gəlməyib.", minutesAgo: 27),
            Self.text(6, from: "operator", "**Yoxladım.** Kuryer bu gün saat 18:00-a qədər çatdıracaq.", minutesAgo: 25),
            Self.text(7, from: "user", "Çox sağ olun 🙏", minutesAgo: 24),
            Self.text(8, from: "operator", "Buyurun. Başqa sualınız olsa, yazın.", minutesAgo: 24),
            Self.message(9, from: "bot", type: "form", content: form, fallback: "Ad, telefon və email yazın",
                         minutesAgo: 23),
        ].compactMap { $0 }
    }

    private static func text(_ seq: Int, from sender: String, _ text: String, minutesAgo: Double) -> Message? {
        message(seq, from: sender, type: "text", content: .object(["text": .string(text)]), fallback: text,
                minutesAgo: minutesAgo)
    }

    private static func message(_ seq: Int, from sender: String, type: String, content: JSONValue, fallback: String,
                                minutesAgo: Double) -> Message? {
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
        return ProtocolJSON.parseMessage(.object(fields))
    }

    private func append(_ text: String, from sender: String) {
        if let message = Self.text((stored.last?.seq ?? 0) + 1, from: sender, text, minutesAgo: 0) {
            stored.append(message)
        }
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
    func readByOperator(in conversationId: String) -> Int? { 7 }
    func localFile(of pending: PendingMessage) -> URL? { nil }
    func loadMessages(in conversationId: String) async throws {}
    func loadOlder(in conversationId: String) async throws -> Bool { false }
    func markRead(in conversationId: String) {}
    func setTyping(_ isTyping: Bool, in conversationId: String) {}

    func sendText(_ text: String, in conversationId: String, replyTo: String?) -> PendingMessage {
        append(text, from: "user")
        if text.hasSuffix("?") {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self.append("Bəli, yoxlayıb sizə yazacağam.", from: "operator")
            }
        }
        return PendingMessage(text: text, in: conversationId)
    }

    func reply(to message: Message, with button: MessageContent.Button) throws -> PendingMessage {
        throw ClomniError.rejected("demo")
    }

    func goBack(from message: Message) throws -> PendingMessage {
        throw ClomniError.rejected("demo")
    }

    func submitForm(_ message: Message, values: [String: JSONValue]) -> PendingMessage {
        answerable.remove(message.id)
        for observer in observers.values { observer(.messages(conversationId: Self.conversationId)) }
        return PendingMessage(text: "", in: message.conversationId)
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
