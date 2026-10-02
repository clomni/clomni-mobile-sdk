import Foundation

/// iOS's swipe back from the screen's left edge, for the conversation over Home: where a drag may start, how far the
/// screen follows the finger, when letting go goes back, and how much of Home shows behind it.
package enum BackSwipe {
    /// A drag starting this close to the leading edge is a swipe back; anywhere else it is the screen's own.
    package static let edgeZone: Double = 20
    /// Past this share of the width, letting go goes back.
    package static let distanceShare: Double = 1.0 / 3
    /// A flick: where the drag would come to rest (SwiftUI's predicted end) past this share of the width, even when
    /// the finger itself moved less.
    package static let flickShare: Double = 0.6
    /// Home behind moves in from 30% of the width to the left, as UIKit's navigation push does.
    package static let parallax: Double = 0.3

    /// Whether a drag that starts at `x` (from the leading edge) and has moved by `dx`, `dy` is a swipe back: from the
    /// edge zone, and more sideways than up or down, so the transcript's scrolling keeps its own drags.
    package static func begins(atX x: Double, dx: Double, dy: Double) -> Bool {
        x <= edgeZone && dx > 0 && abs(dx) > abs(dy)
    }

    /// How far the conversation is moved: with the finger, never left of where it was nor past the edge.
    package static func offset(translation: Double, width: Double) -> Double {
        min(max(0, translation), max(0, width))
    }

    /// Letting go: back to Home past a third of the width, or on a flick; else the conversation returns. A flick back
    /// towards the edge (its predicted end short of a third) returns it even from past a third, as in UIKit.
    package static func completes(translation: Double, predictedEnd: Double, width: Double) -> Bool {
        guard width > 0, translation > 0 else { return false }
        if predictedEnd > width * flickShare { return true }
        return translation > width * distanceShare && predictedEnd > width * distanceShare
    }

    /// Where Home is while the conversation is `offset` away: -30% of the width at rest, 0 once it is gone.
    package static func behindOffset(offset: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        let progress = min(1, max(0, offset / width))
        return -width * parallax * (1 - progress)
    }
}
