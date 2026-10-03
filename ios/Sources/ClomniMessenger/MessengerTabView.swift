#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Hands the controller's screens to SwiftUI. One per open messenger, shared by Home and Messages, so going back to
/// Home draws it as it was.
@MainActor
final class MessengerModel: ObservableObject {
    @Published private(set) var home: HomeScreen
    @Published private(set) var messages: MessagesScreen
    @Published private(set) var config: MessengerConfig?
    let controller: HomeController
    private var loaded = false

    init(controller: HomeController) {
        self.controller = controller
        home = controller.home
        messages = controller.messages
        config = controller.config
        controller.onChange = { [weak self] in self?.sync() }
    }

    convenience init(engine: ClomniEngine, language: String?, userName: String?, config: MessengerConfig? = nil) {
        self.init(controller: HomeController(source: engine, language: language, userName: userName, config: config))
    }

    /// The cache, then the server: once per open messenger, not each time Home comes back into view.
    func load() async {
        guard !loaded else { return }
        loaded = true
        await controller.load()
    }

    private func sync() {
        home = controller.home
        messages = controller.messages
        config = controller.config
    }
}

/// Home, at the bottom of the messenger's navigation: its cards push Messages and conversations.
struct HomeTabView: View {
    @ObservedObject var model: MessengerModel
    /// `opened_from` of a conversation started here.
    let source: String?
    let coordinator: MessengerCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    private var actions: MessengerActions {
        MessengerActions(
            close: { [coordinator] in coordinator.dismiss() },
            newConversation: { [model, source, coordinator] in
                Task { @MainActor in
                    coordinator.navigate(to: .conversation(await model.controller.startConversation(openedFrom: source)))
                }
            },
            openConversation: { [coordinator] in coordinator.navigate(to: .conversation($0)) },
            openMessages: { [coordinator] in coordinator.navigate(to: .messages) },
            openNews: { [coordinator] in coordinator.navigate(to: .news($0)) },
            retry: { [model] in
                Task { @MainActor in await model.controller.retry() }
            })
    }

    var body: some View {
        HomeView(screen: model.home, theme: theme, actions: actions)
            // Text grows with Dynamic Type up to about twice its size.
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .configCrossfade(model.config)
            .task { await model.load() }
    }
}

/// The conversations, newest first, with back to Home.
struct MessagesTabView: View {
    @ObservedObject var model: MessengerModel
    let coordinator: MessengerCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    var body: some View {
        MessagesView(screen: model.messages, theme: theme, closeLabel: model.home.header.closeLabel,
                     backLabel: model.messages.backLabel,
                     actions: MessengerActions(
                        close: { [coordinator] in coordinator.dismiss() },
                        newConversation: { [model, coordinator] in
                            Task { @MainActor in
                                coordinator.navigate(to: .conversation(
                                    await model.controller.startConversation(openedFrom: coordinator.source)))
                            }
                        },
                        openConversation: { [coordinator] in coordinator.navigate(to: .conversation($0)) },
                        back: { [coordinator] in coordinator.back() },
                        retry: { [model] in Task { @MainActor in await model.controller.retry() } }))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .configCrossfade(model.config)
            .task { await model.load() }
    }
}
#endif
