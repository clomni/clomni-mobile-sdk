#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The brief's example company, for Xcode previews.
enum PreviewData {
    static let config: MessengerConfig? = ProtocolJSON.parseConfig(Data(#"""
    {"version":1,"brand":{"name":"Example","primary_color":"#1F9D63","header_style":"gradient","glow":false},
     "theme":{"mode":"system","launcher":{"enabled":false}},
     "home":{"cards":["send","recent","channels"],
             "channels":[{"type":"instagram","url":"https://instagram.com/example"},
                         {"type":"whatsapp","url":"https://wa.me/994501234567"},
                         {"type":"linkedin","url":"https://linkedin.com/company/example"},
                         {"type":"email","url":"mailto:support@example.com"}]},
     "team":{"show":true,"avatars":[],"reply_time":"Adətən bir neçə dəqiqəyə cavab veririk"},
     "bot":{"name":"Clomni"},"composer":{},"languages":["az","en","ru"],"strings":{},"limits":{},"powered_by":true}
    """#.utf8))

    static let conversation: Conversation? = ProtocolJSON.parseConversation(Data(#"""
    {"id":"conv_5521","status":"open","assignee":{"name":"Leyla"},"unread_count":1,"created_at":"2026-10-01T10:00:00Z",
     "last_message":{"id":"msg_1","conversation_id":"conv_5521","type":"text","created_at":"2026-10-01T10:28:00Z",
       "sender":{"type":"operator","name":"Leyla"},"seq":4,"lang":"az","content":{"text":"Balansınıza 2 AZN qaytarıldı."},
       "fallback_text":"Balansınıza 2 AZN qaytarıldı."}}
    """#.utf8))

    static let presenter = HomePresenter(strings: ClomniStrings(language: "az"),
                                         now: Date(timeIntervalSince1970: 1_790_850_600))

    static func snapshot(loaded: Bool = true, conversations: Bool = true) -> MessengerSnapshot {
        var snapshot = MessengerSnapshot(config: loaded ? config : nil,
                                         conversations: conversations ? [conversation].compactMap { $0 } : [],
                                         userName: "Aysel Məmmədova")
        snapshot.unreadTotal = conversations ? 1 : 0
        snapshot.configLoad = loaded ? .loaded : .loading
        snapshot.conversationsLoad = loaded ? .loaded : .loading
        return snapshot
    }

    static func theme(dark: Bool) -> ClomniTheme {
        ClomniTheme.make(brand: config?.brand, dark: dark)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView(screen: PreviewData.presenter.home(PreviewData.snapshot()), theme: PreviewData.theme(dark: false),
                     actions: MessengerActions())
                .previewDisplayName("Home")
            HomeView(screen: PreviewData.presenter.home(PreviewData.snapshot()), theme: PreviewData.theme(dark: true),
                     actions: MessengerActions())
                .preferredColorScheme(.dark)
                .previewDisplayName("Home, dark")
            HomeView(screen: PreviewData.presenter.home(PreviewData.snapshot(loaded: false)),
                     theme: PreviewData.theme(dark: false), actions: MessengerActions())
                .previewDisplayName("Home, first load")
            HomeView(screen: PreviewData.presenter.home(PreviewData.snapshot()), theme: PreviewData.theme(dark: false),
                     actions: MessengerActions())
                .dynamicTypeSize(.accessibility3)
                .previewDisplayName("Home, largest text")
        }
    }
}

struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessagesView(screen: PreviewData.presenter.messages(PreviewData.snapshot()),
                         theme: PreviewData.theme(dark: false), closeLabel: "Bağla", backLabel: "Geri",
                         actions: MessengerActions())
                .previewDisplayName("Messages")
            MessagesView(screen: PreviewData.presenter.messages(PreviewData.snapshot(conversations: false)),
                         theme: PreviewData.theme(dark: false), closeLabel: "Bağla", backLabel: "Geri",
                         actions: MessengerActions())
                .previewDisplayName("Messages, empty")
        }
    }
}
#endif
