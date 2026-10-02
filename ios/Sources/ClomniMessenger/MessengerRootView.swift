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
    /// How far the swipe back has moved the conversation; 0 when it is not being swiped.
    @State private var swipe: CGFloat = 0

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
            GeometryReader { proxy in
                ZStack {
                    // Home behind, only while the conversation is swiped: in from 30% to the left.
                    if swipe > 0 {
                        homeTabs
                            .offset(x: CGFloat(BackSwipe.behindOffset(offset: Double(swipe), width: Double(proxy.size.width))))
                            .allowsHitTesting(false)
                    }
                    ConversationScreen(engine: engine, conversationId: id,
                                       back: { coordinator.navigate(to: .home) },
                                       close: { coordinator.dismiss() })
                        .offset(x: swipe)
                        .shadow(color: Color.black.opacity(swipe > 0 ? 0.12 : 0), radius: 8)
                        .simultaneousGesture(swipeBack(width: proxy.size.width))
                }
            }
                .id(id)
                // As a navigation push: in from the trailing edge, out the same way on back.
                .transition(.move(edge: .trailing))
        case .home? where model.ready:
            // No swipe here: there is nothing to go back to.
            homeTabs
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

extension MessengerRootView {
    var homeTabs: some View {
        MessengerTabView(model: home, source: model.source, close: { coordinator.dismiss() },
                         openConversation: { coordinator.navigate(to: .conversation($0)) })
    }

    /// iOS's swipe back from the left edge (BackSwipe): the conversation follows the finger; let go past a third of
    /// the width or with a flick and it goes on to Home, else it returns. Only drags that start in the 20 pt zone
    /// and go sideways: the transcript's scrolling and the image viewer (a screen of its own) keep theirs. Without
    /// animation under Reduce Motion.
    func swipeBack(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { drag in
                guard swipe > 0 || BackSwipe.begins(atX: Double(drag.startLocation.x), dx: Double(drag.translation.width),
                                                    dy: Double(drag.translation.height)) else { return }
                swipe = CGFloat(BackSwipe.offset(translation: Double(drag.translation.width), width: Double(width)))
            }
            .onEnded { drag in
                guard swipe > 0 else { return }
                let back = BackSwipe.completes(translation: Double(drag.translation.width),
                                               predictedEnd: Double(drag.predictedEndTranslation.width),
                                               width: Double(width))
                finishSwipe(back: back, width: width)
            }
    }

    private func finishSwipe(back: Bool, width: CGFloat) {
        let still = Transaction(animation: nil)
        guard !reduceMotion else {
            withTransaction(still) {
                swipe = 0
                if back { coordinator.navigate(to: .home) }
            }
            return
        }
        let duration = 0.25
        withAnimation(.easeOut(duration: duration)) { swipe = back ? width : 0 }
        guard back else { return }
        // Off screen: Home takes its place, with no second slide.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            var done = still
            done.disablesAnimations = true
            withTransaction(done) {
                coordinator.navigate(to: .home)
                swipe = 0
            }
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
