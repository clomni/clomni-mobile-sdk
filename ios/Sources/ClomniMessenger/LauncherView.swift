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

/// The optional floating button (DESIGN-PASS-3 E1): a 56 pt circle in the brand colour at the bottom corner with the
/// operator's line mascot in it, 30 pt, white lines when on_primary is light and black ones when it is dark (the
/// original drawings, only shrunk; their optical centre in the middle). A soft shadow (y 4, blur 12, 18%), 0.94 while
/// pressed (120 ms), the unread count on the red 18 pt badge. It lives in a window of its own, only as large as the
/// button and its shadow, so the app's screen below stays untouched; the window exists only while the launcher shows.
@MainActor
final class LauncherController {
    private var window: LauncherWindow?

    /// false when there is no scene in the foreground yet, or no key window to take the safe area from (a cold start
    /// whose `initialize` came first): the caller shows it again once there is.
    @discardableResult
    func show(_ state: LauncherState, config: MessengerConfig?, typeface: Typeface?, themeOverride: ThemeOverride,
              tap: @escaping () -> Void) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive }) else {
            ClomniLog.debug("launcher: no scene in the foreground yet")
            return false
        }
        let window = self.window ?? LauncherWindow(windowScene: scene)
        let button = LauncherButton(state: state, config: config, typeface: typeface, themeOverride: themeOverride,
                                    tap: tap)
        if let host = window.rootViewController as? UIHostingController<LauncherButton> {
            host.rootView = button
        } else {
            let host = UIHostingController(rootView: button)
            host.view.backgroundColor = .clear
            window.rootViewController = host
        }
        // The badge and the shadow stand out of the circle.
        let margin: CGFloat = 16
        let side = CGFloat(LauncherState.size) + 2 * margin
        let screen = scene.coordinateSpace.bounds
        let key = scene.windows.first { $0.isKeyWindow }
        let insets = (key ?? scene.windows.first { !($0 is LauncherWindow) })?.safeAreaInsets ?? .zero
        let edge = CGFloat(LauncherState.edgePadding) - margin
        let x = state.side == .left ? insets.left + edge : screen.width - insets.right - edge - side
        let y = screen.height - insets.bottom - edge - CGFloat(state.bottomPadding) - side
        window.frame = CGRect(x: x, y: y, width: side, height: side)
        if window.isHidden { ClomniLog.debug("launcher shown") }
        window.isHidden = false
        self.window = window
        return key != nil
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// Above the app's own windows, never the key window.
final class LauncherWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var canBecomeKey: Bool { false }
}

struct LauncherButton: View {
    let state: LauncherState
    let config: MessengerConfig?
    let typeface: Typeface?
    let themeOverride: ThemeOverride
    let tap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ClomniTheme {
        ClomniTheme.make(config: config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    var body: some View {
        Button(action: tap) {
            mascot
                .frame(width: CGFloat(LauncherState.size), height: CGFloat(LauncherState.size))
                .background(Circle().fill(theme.colors.primary.color)
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 4))
                .overlay(alignment: .topTrailing) {
                    if let badge = state.badge {
                        Text(badge)
                            .clomniFixedFont(11, .bold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, CGFloat(ClomniTheme.Space.xxs))
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(theme.colors.unread.color))
                            .overlay(Capsule().stroke(theme.colors.background.color, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(LauncherPressStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .accessibilityIdentifier("clomni.launcher")
        .environment(\.clomniTypeface, typeface)
        .environment(\.clomniThemeOverride, themeOverride)
    }

    private var mascot: some View {
        let name = LauncherState.whiteMascot(on: theme.colors.onPrimary)
            ? "clomni_launcher_mascot_white" : "clomni_launcher_mascot_black"
        return Image(name, bundle: ClomniResources.bundle("ClomniMessenger_Media"))
            .resizable()
            .interpolation(.high)
            .frame(width: CGFloat(LauncherState.mascotSize), height: CGFloat(LauncherState.mascotSize))
            .accessibilityHidden(true)
    }
}

/// Pressed, the launcher gives a little (0.97) and springs back (M6).
private struct LauncherPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressScale(configuration.isPressed, CGFloat(LauncherState.pressedScale))
    }
}
#endif
