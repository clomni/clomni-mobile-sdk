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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: MessengerRootModel, coordinator: MessengerCoordinator, engine: ClomniEngine) {
        self.model = model
        self.coordinator = coordinator
        self.engine = engine
        _home = StateObject(wrappedValue: MessengerModel(engine: engine, language: nil, userName: nil))
    }

    /// The app's setTheme from the first frame: this view sets the environment value for the screens under it, so it
    /// reads the model's, not its own environment's.
    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: model.themeOverride)
    }

    var body: some View {
        content
            .environment(\.clomniTypeface, model.typeface)
            .environment(\.clomniThemeOverride, model.themeOverride)
            // The panel's (or the app's) light or dark mode for the system's controls too.
            .preferredColorScheme(colorScheme(model.themeOverride.mode ?? model.config?.theme.mode))
            .configCrossfade(model.config)
            // The push's timing; Reduce Motion: no movement.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: model.route)
            .task { await coordinator.prepare() }
    }

    private func colorScheme(_ mode: MessengerConfig.Mode?) -> ColorScheme? {
        switch mode {
        case .light?: return .light
        case .dark?: return .dark
        default: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .conversation(let id)? where model.ready:
            ConversationScreen(engine: engine, conversationId: id,
                               back: { coordinator.navigate(to: .home) },
                               close: { coordinator.dismiss() })
                .id(id)
                // As a navigation push: in from the trailing edge, out the same way on back.
                .transition(.move(edge: .trailing))
        case .home? where model.ready:
            MessengerTabView(model: home, source: model.source, close: { coordinator.dismiss() },
                             openConversation: { coordinator.navigate(to: .conversation($0)) })
        default:
            // Not ready yet: grey blocks in the brand's colour, ✕ still working.
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

    init(engine: ClomniEngine, conversationId: String, back: @escaping () -> Void, close: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ChatModel(engine: engine, conversationId: conversationId, language: nil))
        self.back = back
        self.close = close
    }

    var body: some View {
        ChatView(model: model, back: back, close: close)
    }
}
#endif
