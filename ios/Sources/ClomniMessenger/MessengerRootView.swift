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
    /// How the screen comes into view (CM-346 § 5.1); none for the UI tests' demo screens.
    var entry: ScreenEntryModel?

    var body: some View {
        content
            .environment(\.clomniScreenEntry, entry)
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

/// Home: the spinner on the page until the SDK is ready and the entry's minimum has passed ("Yenidən cəhd et" when
/// getting ready failed), then Home itself (CM-346 § 5.1).
struct HomeScreenRoot: View {
    @ObservedObject var model: MessengerRootModel
    @ObservedObject var home: MessengerModel
    let coordinator: MessengerCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .entryGate(ready: model.preparationFailed, background: HomeView.page(theme), theme: theme,
                               label: ClomniStrings(language: model.config.speaks(model.language),
                                                    overrides: model.config?.strings ?? [:])[.loading])
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.ready)
        .task { await coordinator.prepare() }
    }
}

/// One conversation with its own model, made once per conversation id.
struct ConversationScreen: View {
    @StateObject private var model: ChatModel
    let back: () -> Void
    let close: () -> Void

    init(source: ChatDataSource, conversationId: String, language: String?, config: MessengerConfig?,
         back: @escaping () -> Void, close: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ChatModel(controller: ChatController(
            source: source, conversationId: conversationId, language: language, config: config)))
        self.back = back
        self.close = close
    }

    var body: some View {
        ChatView(model: model, back: back, close: close)
    }
}
#endif
