#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// DESIGN-PASS-3 M1–M10 ("Intercom kimi"): everything moves on a spring or on the emphasized easing, nothing jumps;
/// the same numbers as Android. With Reduce Motion on, things only fade or stand still (M10).
enum Motion {
    /// The sheet's spring (damping 0.86, stiffness ≈ 400), for anything that travels: scrolling to a message too.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Material's emphasized decelerate over `duration` seconds.
    static func decelerate(_ duration: Double) -> Animation {
        .timingCurve(0.05, 0.7, 0.1, 1, duration: duration)
    }
}
#endif
