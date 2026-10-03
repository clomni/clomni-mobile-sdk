#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The language choice of the brief (4.2) and an operator's answer, for Xcode previews.
enum ChatPreviewData {
    static func message(_ json: String) -> Message? {
        ProtocolJSON.parseMessage(Data(json.utf8))
    }

    static let languages = message(#"""
    {"id":"msg_1","conversation_id":"conv_1","type":"quick_replies","sender":{"type":"bot","name":"Clomni"},
     "created_at":"2026-10-01T10:30:00Z","seq":1,"lang":"az","flow":{"flow_id":"flw_lang","node_id":"L","interactive":true},
     "content":{"text":"Salam, Clomni-yə xoş gəlmisiniz. Zəhmət olmasa dil seçin.","layout":"vertical",
       "buttons":[{"id":"az","title":"Azərbaycan dili","icon":"🇦🇿","payload":"set_lang:az"},
                  {"id":"en","title":"English","icon":"🇬🇧","payload":"set_lang:en"},
                  {"id":"ru","title":"Русский","icon":"🇷🇺","payload":"set_lang:ru"}]},
     "fallback_text":"Dil seçin"}
    """#)

    static let user = message(#"""
    {"id":"msg_2","client_id":"c1","conversation_id":"conv_1","type":"text","sender":{"type":"user"},
     "created_at":"2026-10-01T10:31:00Z","seq":2,"lang":"az","content":{"text":"Gedişim bitmədi"},
     "fallback_text":"Gedişim bitmədi"}
    """#)

    static let operatorReply = message(#"""
    {"id":"msg_3","conversation_id":"conv_1","type":"text","sender":{"type":"operator","name":"Leyla"},
     "created_at":"2026-10-01T10:31:30Z","seq":3,"lang":"az",
     "content":{"text":"**Yoxladıq.** Balansınıza *2 AZN* qaytarıldı. [Şərtlər](https://apar.az)"},
     "fallback_text":"Yoxladıq."}
    """#)

    static func screen(_ messages: [Message?], answerable: Set<String> = []) -> ChatScreen {
        var snapshot = ChatSnapshot(config: PreviewData.config, messages: messages.compactMap { $0 })
        snapshot.answerable = answerable
        snapshot.load = .loaded
        return ChatPresenter(strings: ClomniStrings(language: "az"), now: Date(timeIntervalSince1970: 1_790_850_720))
            .screen(snapshot)
    }
}

/// The conversation without a controller: header, transcript, composer.
struct ChatPreviewScene: View {
    let screen: ChatScreen
    let theme: ClomniTheme

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(header: screen.header, theme: theme, back: {}, close: {})
            ScrollView { ChatTranscript(items: screen.items, theme: theme, actions: ChatActions()) }
            ComposerView(composer: screen.composer, theme: theme, text: .constant(""), writeAnyway: .constant(false),
                         staged: .constant(nil),
                         send: {}, attach: {}, startNew: {})
        }
        .background(theme.colors.background.color.ignoresSafeArea())
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChatPreviewScene(screen: ChatPreviewData.screen([ChatPreviewData.languages], answerable: ["msg_1"]),
                             theme: PreviewData.theme(dark: false))
                .previewDisplayName("Language choice")
            ChatPreviewScene(screen: ChatPreviewData.screen([ChatPreviewData.languages, ChatPreviewData.user,
                                                             ChatPreviewData.operatorReply]),
                             theme: PreviewData.theme(dark: true))
                .preferredColorScheme(.dark)
                .previewDisplayName("Operator, dark")
        }
    }
}
#endif
