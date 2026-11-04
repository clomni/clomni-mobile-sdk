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

/// The drag to the right that answers a message (DESIGN-PASS-3 F2): the bubble follows the finger at 70%, and let go
/// past the threshold it answers. The user's own messages stand at the right edge, with little room to the right
/// (TestFlight #21: «öz mesajına yanıt vermək olmur»): theirs answer at 40 pt of finger, an operator's at 80.
package enum ReplySwipe {
    package static let resistance: CGFloat = 0.7

    /// How far the bubble has followed when letting go answers it.
    package static func threshold(outgoing: Bool) -> CGFloat {
        outgoing ? 28 : 56
    }

    /// Where the bubble is for `translation` of finger to the right; never left, and a little past the threshold at most.
    package static func pulled(_ translation: CGFloat, outgoing: Bool) -> CGFloat {
        min(max(translation * resistance, 0), threshold(outgoing: outgoing) + 24)
    }

    package static func answers(_ translation: CGFloat, outgoing: Bool) -> Bool {
        pulled(translation, outgoing: outgoing) >= threshold(outgoing: outgoing)
    }
}
