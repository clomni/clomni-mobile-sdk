#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

// CM-342 (Apar Ride, iOS 18+): a drag that started on a message bubble did not move the conversation. Since iOS 18
// SwiftUI's gestures are UIKit recognizers of their own, and a DragGesture on a bubble (the swipe to answer, even as a
// simultaneous gesture, and the waveform's) took the touch from the ScrollView's pan. This pan is UIKit's, and it
// fails as soon as the finger moves more up or down than sideways: the touch is then the list's alone.

/// A pan that starts only sideways (to the right only with `rightOnly`); a vertical start fails it at once.
final class SidewaysPanRecognizer: UIPanGestureRecognizer {
    var rightOnly = false
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if start == nil { start = touches.first?.location(in: nil) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let start, let point = touches.first?.location(in: nil) {
            let dx = point.x - start.x, dy = point.y - start.y
            guard hypot(dx, dy) >= DragDirection.slop else { return }
            if !DragDirection.sideways(dx: dx, dy: dy, rightOnly: rightOnly) {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
    }

    /// The list's pan waits for this one to decide: a drag across is this pan's, not taken first by the scroll view
    /// (which otherwise begins on any move); a vertical one fails it within `DragDirection.slop`, and the list scrolls.
    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        isEnabled && other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}

#if compiler(>=6.0)
/// `SidewaysPanRecognizer` in SwiftUI (iOS 18+): `changed` with the finger's sideways travel from where it started and
/// where it is in the view's own space; `ended` once it is let go (`finished`) or the system took it.
@available(iOS 18.0, *)
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var rightOnly = false
    var enabled = true
    let changed: (_ translation: CGFloat, _ location: CGPoint) -> Void
    let ended: (_ finished: Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> SidewaysPanRecognizer {
        let pan = SidewaysPanRecognizer()
        pan.maximumNumberOfTouches = 1
        updateUIGestureRecognizer(pan, context: context)
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: SidewaysPanRecognizer, context: Context) {
        recognizer.rightOnly = rightOnly
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: SidewaysPanRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            changed(recognizer.translation(in: recognizer.view).x, context.converter.localLocation)
        case .ended:
            ended(true)
        case .cancelled, .failed:
            ended(false)
        default:
            break
        }
    }
}
#endif
#endif
