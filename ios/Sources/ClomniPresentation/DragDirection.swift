import Foundation

/// Which way a drag on a bubble goes, decided once the finger has moved `slop` (CM-342): along (the swipe to answer,
/// the waveform's playhead) or up and down, which is always the list's.
package enum DragDirection {
    package static let slop: CGFloat = 4

    /// More across than up or down (and to the right with `rightOnly`).
    package static func sideways(dx: CGFloat, dy: CGFloat, rightOnly: Bool) -> Bool {
        (rightOnly ? dx : abs(dx)) > abs(dy)
    }

    /// Moved `slop` or more, and more up or down than across.
    package static func vertical(_ move: CGSize) -> Bool {
        (move.width * move.width + move.height * move.height).squareRoot() >= slop
            && !sideways(dx: move.width, dy: move.height, rightOnly: false)
    }
}
