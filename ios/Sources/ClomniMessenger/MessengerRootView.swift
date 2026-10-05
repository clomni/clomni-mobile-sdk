#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Every screen of the messenger sits in one of these: the app's font and setTheme, and the panel's (or the app's)
/// light or dark mode for the system's controls too.
struct ScreenRoot<Content: View>: View {
    @ObservedObject var model: MessengerRootModel
    let content: Content

    var body: some View {
        content
            .environment(\.clomniTypeface, model.typeface)
            .environment(\.clomniThemeOverride, model.themeOverride)
            .preferredColorScheme(Self.colorScheme(model.themeOverride.mode ?? model.config?.theme.mode))
            .configCrossfade(model.config)
    }

    static func colorScheme(_ mode: MessengerConfig.Mode?) -> ColorScheme? {
        switch mode {
        case .light?: return .light
        case .dark?: return .dark
        default: return nil
        }
    }
}

/// Home: the brand's grey blocks with the loading indicator until the SDK is ready ("Yenidən cəhd et" when getting
/// ready failed), then Home itself, fading in over 200 ms.
struct HomeScreenRoot: View {
    @ObservedObject var model: MessengerRootModel
    @ObservedObject var home: MessengerModel
    let coordinator: MessengerCoordinator
    @Environment(\.colorScheme) private var colorScheme

    /// setTheme from the first frame: the model's, which this view's own environment does not have yet.
    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: model.themeOverride)
    }

    var body: some View {
        ZStack {
            if model.ready {
                HomeTabView(model: home, source: model.source, coordinator: coordinator)
                    .transition(.opacity)
            } else {
                HomeView(screen: HomePresenter(strings: ClomniStrings(language: model.config.speaks(model.language),
                                                                      overrides: model.config?.strings ?? [:]),
                                               now: Date()).preparing(failed: model.preparationFailed),
                         theme: theme,
                         actions: MessengerActions(close: { coordinator.dismiss() },
                                                   retry: { Task { await coordinator.prepare() } }))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.ready)
        // M1: the sheet itself is the system's (pageSheet, on its spring); its content fades in 120 ms after it.
        .entrance(rise: 0, delay: 0.12)
        .task { await coordinator.prepare() }
    }
}

/// The conversations, pushed from Home's "Mesajlar" card.
struct MessagesScreenRoot: View {
    @ObservedObject var home: MessengerModel
    let coordinator: MessengerCoordinator

    var body: some View {
        MessagesTabView(model: home, coordinator: coordinator)
    }
}

/// One conversation with its own model, made once per conversation id.
struct ConversationScreen: View {
    @StateObject private var model: ChatModel
    let back: () -> Void
    let close: () -> Void

    init(engine: ClomniEngine, conversationId: String, language: String?, back: @escaping () -> Void,
         close: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ChatModel(engine: engine, conversationId: conversationId, language: language))
        self.back = back
        self.close = close
    }

    var body: some View {
        ChatView(model: model, back: back, close: close)
    }
}
#endif
