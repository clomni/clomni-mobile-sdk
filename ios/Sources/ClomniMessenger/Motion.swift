#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// DESIGN-PASS-3 M1–M10 ("Intercom kimi"): everything moves on a spring or on the emphasized easing, nothing jumps;
/// the same numbers as Android. The sheet (M1) and push/pop (M2) are the system's own. With Reduce Motion on,
/// things only fade or stand still (M10).
enum Motion {
    /// The sheet's spring (damping 0.86, stiffness ≈ 400), for anything that travels: scrolling to a message too.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// The offline capsule's 200 ms spring (CM-077): damping 0.86, stiffness ≈ 1000.
    static let capsule = Animation.spring(response: 0.2, dampingFraction: 0.86)
    /// A press and its release (M6): damping 0.6, stiffness ≈ 800.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)

    /// Material's emphasized decelerate over `duration` seconds.
    static func decelerate(_ duration: Double) -> Animation {
        .timingCurve(0.05, 0.7, 0.1, 1, duration: duration)
    }

    /// Material's emphasized accelerate over `duration` seconds: for what leaves.
    static func accelerate(_ duration: Double) -> Animation {
        .timingCurve(0.3, 0, 0.8, 0.15, duration: duration)
    }

    /// How a new item of the transcript comes in (M3, M4): an incoming bubble rises 8 from 0.97, the user's own 12
    /// out of the composer, the typing bubble grows in; lines fade. With Reduce Motion everything only fades. One that
    /// goes is gone in that frame: nothing fades out over what takes its place.
    static func arrival(_ item: ChatItem, still: Bool) -> AnyTransition {
        var rise: CGFloat = 4, from: CGFloat = 0.9, anchor = UnitPoint.bottomLeading
        switch item {
        case .bubble(let bubble) where bubble.side == .incoming: (rise, from) = (8, 0.97)
        case .bubble: (rise, from, anchor) = (12, 1, .bottomTrailing)
        case .typing: break
        default: return .asymmetric(insertion: .opacity, removal: .identity)
        }
        guard !still else { return .asymmetric(insertion: .opacity, removal: .identity) }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: rise)).combined(with: .scale(scale: from, anchor: anchor)),
                           removal: .identity)
    }
}

extension View {
    /// M6: gives to `scale` on a spring while pressed and springs back; with Reduce Motion it stays still.
    func pressScale(_ pressed: Bool, _ scale: CGFloat = 0.97) -> some View {
        let still = UIAccessibility.isReduceMotionEnabled
        return scaleEffect(pressed && !still ? scale : 1).animation(still ? nil : Motion.press, value: pressed)
    }

    /// Comes in once, `delay` seconds after it first appears: `rise` pt up and fading in (M5, M8). Not when `enabled`
    /// is false; with Reduce Motion it only fades.
    func entrance(rise: CGFloat, delay: Double = 0, enabled: Bool = true) -> some View {
        modifier(Entrance(rise: rise, delay: delay, enabled: enabled))
    }
}

private struct Entrance: ViewModifier {
    let rise: CGFloat
    let delay: Double
    let enabled: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.clomniLoadsRemoteImages) private var live

    func body(content: Content) -> some View {
        let hidden = enabled && live && !shown
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && !reduceMotion ? rise : 0)
            .onAppear {
                guard hidden else { return }
                withAnimation(Motion.decelerate(0.2).delay(delay)) { shown = true }
            }
    }
}

/// M6: a card gives to 0.97 while pressed and dims a little, as PlainButtonStyle does.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .pressScale(configuration.isPressed)
    }
}
#endif
