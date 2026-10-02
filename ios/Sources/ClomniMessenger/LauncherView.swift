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

/// The optional floating button: a 56 pt brand-coloured circle at the bottom corner, the unread count on it. It
/// lives in a window of its own, only as large as the button, so the app's screen below stays untouched; the window
/// exists only while the launcher shows.
@MainActor
final class LauncherController {
    private var window: LauncherWindow?

    func show(_ state: LauncherState, config: MessengerConfig?, typeface: Typeface?, tap: @escaping () -> Void) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let window = self.window ?? LauncherWindow(windowScene: scene)
        let button = LauncherButton(state: state, config: config, typeface: typeface, tap: tap)
        if let host = window.rootViewController as? UIHostingController<LauncherButton> {
            host.rootView = button
        } else {
            let host = UIHostingController(rootView: button)
            host.view.backgroundColor = .clear
            window.rootViewController = host
        }
        // The badge may stand out of the circle by a few points.
        let side = CGFloat(LauncherState.size) + 12
        let screen = scene.coordinateSpace.bounds
        let insets = scene.windows.first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
        let edge = CGFloat(LauncherState.edgePadding) - 6
        let x = state.side == .left ? insets.left + edge : screen.width - insets.right - edge - side
        let y = screen.height - insets.bottom - edge - CGFloat(state.bottomPadding) - side
        window.frame = CGRect(x: x, y: y, width: side, height: side)
        window.isHidden = false
        self.window = window
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
    let tap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride

    private var theme: ClomniTheme {
        ClomniTheme.make(config: config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    var body: some View {
        Button(action: tap) {
            Image(systemName: "message.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.colors.onPrimary.color)
                .frame(width: CGFloat(LauncherState.size), height: CGFloat(LauncherState.size))
                .background(Circle().fill(theme.colors.primary.color))
                .shadow(color: Color.black.opacity(0.2), radius: 7, x: 0, y: 4)
                .overlay(alignment: .topTrailing) {
                    if let badge = state.badge {
                        Text(badge)
                            .clomniFixedFont(11, .bold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(theme.colors.unread.color))
                            .overlay(Capsule().stroke(theme.colors.background.color, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .environment(\.clomniTypeface, typeface)
    }
}
#endif
