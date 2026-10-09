#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Does what the coordinator says in UIKit: presents the messenger as a page sheet from the top view controller (the
/// app stays visible behind it, a swipe down closes it), its screens in a navigation controller (the system's push,
/// pop and swipe back), and shows the launcher in a window of its own. Nothing at all while the messenger is closed
/// and the launcher off.
@MainActor
final class UIKitMessenger: NSObject, MessengerRenderer, UIAdaptivePresentationControllerDelegate,
    UINavigationControllerDelegate {
    private let engine: ClomniEngine
    private weak var coordinator: MessengerCoordinator?
    private let rootModel = MessengerRootModel()
    private let launcher = LauncherController()
    private var navigation: MessengerNavigationController?
    /// The routes of `navigation`'s view controllers, in order.
    private var shown: [MessengerRoute] = []
    /// Home's state, kept while the messenger is open: going back to Home draws it as it was (DESIGN-PASS-2 9).
    private var home: MessengerModel?
    private var typeface: Typeface?
    private var themeOverride = ThemeOverride()
    /// Waiting for a window to present from (`present`).
    private var windowObservers: [NSObjectProtocol] = []

    init(engine: ClomniEngine, coordinator: MessengerCoordinator) {
        self.engine = engine
        self.coordinator = coordinator
        super.init()
        // A launcher with no session yet (no network at launch) tries again when the network is back.
        NetworkMonitor.shared.follow(self) { messenger, offline in
            guard !offline, let coordinator = messenger.coordinator else { return }
            Task { await coordinator.networkAvailable() }
        }
    }

    func setThemeOverride(_ override: ThemeOverride) {
        themeOverride = override
        rootModel.themeOverride = override
        render()
    }

    func setTypeface(_ family: String?) {
        typeface = family.flatMap(Typeface.installed)
        if let family, typeface == nil {
            ClomniLog.warning("font family \"\(family)\" is not in the app; the system font stays")
        }
        rootModel.typeface = typeface
        render()
    }

    func render() {
        guard let coordinator else { return }
        rootModel.update(from: coordinator)
        // Dismissed by the app (all its presented controllers, say): presented again if the route still says so.
        if navigation?.presentingViewController == nil { close() }
        if !coordinator.stack.isEmpty {
            if navigation == nil { present(coordinator) }
            follow(coordinator.stack)
        } else if let navigation {
            close()
            navigation.dismiss(animated: true)
        }
        if let state = coordinator.launcher {
            let placed = launcher.show(state, config: coordinator.config, typeface: typeface, themeOverride: themeOverride) {
                [weak coordinator] in
                coordinator?.present(source: "launcher")
            }
            // An initialize that came before the app's scene and window (CM-087): placed again once they are up.
            _ = placed
        } else {
            launcher.hide()
        }
    }

    /// Lets go of the sheet without touching its screens: closed (pulled down, ✕, `Clomni.dismiss`) it goes down still
    /// showing the screen it showed, not Home (DESIGN-PASS-3 C4). The next opening is a new navigation, at Home.
    private func close() {
        navigation = nil
        shown = []
        home = nil
    }

    private func present(_ coordinator: MessengerCoordinator) {
        // A tap on a notification at a cold start can come before the app's window is up: presented once it is.
        guard let top = Self.topViewController(), top.viewIfLoaded?.window != nil else { return waitForWindow() }
        stopWaitingForWindow()
        let navigation = Self.sheet()
        navigation.delegate = self
        navigation.presentationController?.delegate = self
        self.navigation = navigation
        shown = []
        home = MessengerModel(engine: engine, language: coordinator.language, userName: nil, config: coordinator.config)
        follow(coordinator.stack, animated: false)
        top.present(navigation, animated: true)
    }

    private func waitForWindow() {
        guard windowObservers.isEmpty else { return }
        ClomniLog.debug("no window to show the messenger or its launcher in yet")
        for name in [UIWindow.didBecomeKeyNotification, UIScene.didActivateNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopWaitingForWindow()
                    self?.render()
                }
            })
        }
    }

    private func stopWaitingForWindow() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
    }

    /// Brings the navigation stack to `stack`: a push or a pop when only the top changed, else the whole stack.
    private func follow(_ stack: [MessengerRoute], animated: Bool = true) {
        guard let navigation, stack != shown else { return }
        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        let kept = zip(shown, stack).prefix { $0 == $1 }.count
        var controllers = Array(navigation.viewControllers.prefix(kept))
        for route in stack.dropFirst(kept) { controllers.append(host(route)) }
        shown = stack
        navigation.setViewControllers(controllers, animated: animate)
    }

    private func host(_ route: MessengerRoute) -> UIViewController {
        Self.host(ScreenRoot(model: rootModel, content: screen(route)))
    }

    /// The messenger's sheet: a card over the app, which stays visible behind it; swiping it down closes the messenger.
    /// Its screens are in the system's navigation, the bar hidden. The UI tests' demo conversation is in one too.
    static func sheet() -> MessengerNavigationController {
        let navigation = MessengerNavigationController()
        navigation.modalPresentationStyle = .pageSheet
        return navigation
    }

    /// One screen of the sheet.
    static func host<Content: View>(_ root: Content) -> UIViewController {
        let host = UIHostingController(rootView: root)
        // The screens draw their own bars, ✕ and back.
        host.navigationItem.largeTitleDisplayMode = .never
        return host
    }

    @ViewBuilder
    private func screen(_ route: MessengerRoute) -> some View {
        if let coordinator {
            switch route {
            case .home:
                HomeScreenRoot(model: rootModel, home: home ?? MessengerModel(engine: engine, language: coordinator.language, userName: nil),
                               coordinator: coordinator)
            case .messages:
                MessagesScreenRoot(home: home ?? MessengerModel(engine: engine, language: coordinator.language, userName: nil),
                                   coordinator: coordinator)
            case .news(let id):
                NewsScreenView(model: home ?? MessengerModel(engine: engine, language: coordinator.language, userName: nil), id: id,
                               coordinator: coordinator)
            case .conversation(let id):
                ConversationScreen(engine: engine, conversationId: id, language: coordinator.language,
                                   config: coordinator.config,
                                   back: { [weak coordinator] in coordinator?.back() },
                                   close: { [weak coordinator] in coordinator?.dismiss() })
            }
        }
    }

    // MARK: - The system's own moves

    /// The sheet was swiped down: the messenger is closed.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        close()
        coordinator?.dismiss()
    }

    /// The swipe back (or any pop the navigation controller made): the coordinator follows.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                              animated: Bool) {
        let count = navigationController.viewControllers.count
        guard count < shown.count else { return }
        shown.removeLast(shown.count - count)
        coordinator?.poppedTo(count: count)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !($0 is LauncherWindow) }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The messenger's navigation: the bar is hidden (each screen draws its own), and the swipe from the left edge still
/// goes back, as everywhere on iOS.
final class MessengerNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = self
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// The coordinator's state for SwiftUI.
@MainActor
final class MessengerRootModel: ObservableObject {
    @Published private(set) var route: MessengerRoute?
    @Published private(set) var ready = false
    @Published private(set) var config: MessengerConfig?
    @Published private(set) var source: String?
    @Published private(set) var preparationFailed = false
    /// `Clomni.setLanguage`.
    @Published private(set) var language: String?
    @Published var typeface: Typeface?
    @Published var themeOverride = ThemeOverride()

    func update(from coordinator: MessengerCoordinator) {
        if route != coordinator.route { route = coordinator.route }
        if ready != (coordinator.readiness == .ready) { ready = coordinator.readiness == .ready }
        if config != coordinator.config { config = coordinator.config }
        if source != coordinator.source { source = coordinator.source }
        if preparationFailed != coordinator.preparationFailed { preparationFailed = coordinator.preparationFailed }
        if language != coordinator.language { language = coordinator.language }
    }
}
#endif
