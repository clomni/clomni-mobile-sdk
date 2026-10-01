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

/// Does what the coordinator says in UIKit: presents the messenger full screen from the top view controller, and
/// shows the launcher in a window of its own, only as large as the button. Nothing at all while the messenger is
/// closed and the launcher off.
@MainActor
final class UIKitMessenger: MessengerRenderer {
    private let engine: ClomniEngine
    private weak var coordinator: MessengerCoordinator?
    private let rootModel = MessengerRootModel()
    private let launcher = LauncherController()
    private var presented: UIViewController?
    private var typeface: Typeface?

    init(engine: ClomniEngine, coordinator: MessengerCoordinator) {
        self.engine = engine
        self.coordinator = coordinator
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
        if presented?.presentingViewController == nil { presented = nil }
        if coordinator.route != nil, presented == nil {
            present(MessengerRootView(model: rootModel, coordinator: coordinator, engine: engine))
        } else if coordinator.route == nil, let presented {
            self.presented = nil
            presented.dismiss(animated: true)
        }
        if let state = coordinator.launcher {
            launcher.show(state, config: coordinator.config, typeface: typeface) { [weak coordinator] in
                coordinator?.present(source: "launcher")
            }
        } else {
            launcher.hide()
        }
    }

    private func present(_ root: MessengerRootView) {
        guard let top = Self.topViewController() else {
            return ClomniLog.error("no window to present the messenger from")
        }
        let host = UIHostingController(rootView: root)
        // Full screen, sliding up (a fade with Reduce Motion); closing returns the app to where it was.
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = UIAccessibility.isReduceMotionEnabled ? .crossDissolve : .coverVertical
        presented = host
        top.present(host, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !($0 is LauncherWindow) }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The coordinator's state for SwiftUI.
@MainActor
final class MessengerRootModel: ObservableObject {
    @Published private(set) var route: MessengerRoute?
    @Published private(set) var ready = false
    @Published private(set) var config: MessengerConfig?
    @Published private(set) var source: String?
    @Published var typeface: Typeface?

    func update(from coordinator: MessengerCoordinator) {
        if route != coordinator.route { route = coordinator.route }
        if ready != (coordinator.readiness == .ready) { ready = coordinator.readiness == .ready }
        if config != coordinator.config { config = coordinator.config }
        if source != coordinator.source { source = coordinator.source }
    }
}
#endif
