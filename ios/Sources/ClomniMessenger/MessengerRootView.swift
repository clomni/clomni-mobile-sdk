#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The presented messenger: skeletons until the SDK is ready (never an empty screen), then Home or a conversation
/// as the coordinator's route says.
struct MessengerRootView: View {
    @ObservedObject var model: MessengerRootModel
    let coordinator: MessengerCoordinator
    let engine: ClomniEngine
    @StateObject private var home: MessengerModel
    @Environment(\.colorScheme) private var colorScheme

    init(model: MessengerRootModel, coordinator: MessengerCoordinator, engine: ClomniEngine) {
        self.model = model
        self.coordinator = coordinator
        self.engine = engine
        _home = StateObject(wrappedValue: MessengerModel(engine: engine, language: nil, userName: nil))
    }

    private var theme: ClomniTheme {
        let brand = model.config?.brand
        let dark = ClomniTheme.isDark(brand?.theme, systemIsDark: colorScheme == .dark)
        return ClomniTheme.make(brand: brand, dark: dark)
    }

    var body: some View {
        content
            .environment(\.clomniTypeface, model.typeface)
            .task { await coordinator.prepare() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .conversation(let id)? where model.ready:
            ConversationScreen(engine: engine, conversationId: id,
                               back: { coordinator.navigate(to: .home) },
                               close: { coordinator.dismiss() },
                               started: { coordinator.conversationStarted($0) })
                .id(id)
        case .home? where model.ready:
            MessengerTabView(model: home, source: model.source, close: { coordinator.dismiss() },
                             openConversation: { coordinator.navigate(to: .conversation($0)) },
                             conversationStarted: { coordinator.conversationStarted($0) })
        default:
            // Not ready yet, or a conversation being started: grey blocks in the brand's colour, ✕ still working.
            // When getting ready failed, "Yenidən cəhd et" instead.
            HomeView(screen: HomePresenter(strings: ClomniStrings(language: model.config?.languages.first),
                                           now: Date()).preparing(failed: model.preparationFailed),
                     theme: theme,
                     actions: MessengerActions(close: { coordinator.dismiss() },
                                               retry: { Task { await coordinator.prepare() } }))
        }
    }
}

/// One conversation with its own model, made once per conversation id.
struct ConversationScreen: View {
    @StateObject private var model: ChatModel
    let back: () -> Void
    let close: () -> Void
    let started: (String) -> Void

    init(engine: ClomniEngine, conversationId: String, back: @escaping () -> Void, close: @escaping () -> Void,
         started: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: ChatModel(engine: engine, conversationId: conversationId, language: nil))
        self.back = back
        self.close = close
        self.started = started
    }

    var body: some View {
        ChatView(model: model, back: back, close: close, conversationStarted: started)
    }
}
#endif
