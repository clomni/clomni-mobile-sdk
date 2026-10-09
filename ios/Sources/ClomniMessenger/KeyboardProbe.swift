#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// How much of a screen the keyboard covers, measured from UIKit's own keyboard notifications in that screen's
/// coordinates (operator, 2026-10-07, H1). SwiftUI's keyboard avoidance did not reach the conversation inside the
/// messenger's page sheet on an iPhone: the keyboard came up over the transcript and nothing moved. So the screen
/// ignores the keyboard's safe area and lifts itself by what this reports, on the keyboard's own animation.
///
/// Put it behind the part of the screen that should end on the keyboard (`.background`): it reports how far into that
/// part the keyboard reaches, 0 while the keyboard is down or floats (iPad) above the bottom of the screen.
struct KeyboardProbe: UIViewRepresentable {
    /// The overlap in points, and the keyboard's animation to follow it with (nil: no animation).
    let report: (CGFloat, Animation?) -> Void

    func makeUIView(context: Context) -> KeyboardProbeView {
        let view = KeyboardProbeView()
        view.report = report
        return view
    }

    func updateUIView(_ view: KeyboardProbeView, context: Context) {
        view.report = report
    }
}

final class KeyboardProbeView: UIView {
    var report: (CGFloat, Animation?) -> Void = { _, _ in }
    /// The keyboard's frame in screen coordinates, nil while it is down.
    private var keyboard: CGRect?
    private var reported: CGFloat = 0
    private let observers = KeyboardObservers()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            observers.tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let hides = note.name == UIResponder.keyboardWillHideNotification
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                    .doubleValue ?? 0
                MainActor.assumeIsolated {
                    self?.keyboard = hides ? nil : end
                    self?.measure(duration: duration)
                }
            })
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    // The sheet resized or turned with the keyboard up: measured again, after the layout pass that moved it.
    override func layoutSubviews() {
        super.layoutSubviews()
        DispatchQueue.main.async { [weak self] in self?.measure(duration: 0) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.measure(duration: 0) }
    }

    private func measure(duration: Double) {
        guard let window else { return }
        var overlap: CGFloat = 0
        if let keyboard, keyboard.maxY >= window.screen.bounds.maxY - 1 {
            let frame = convert(keyboard, from: window.screen.coordinateSpace)
            overlap = max(0, bounds.maxY - frame.minY)
        }
        guard abs(overlap - reported) > 0.5 else { return }
        reported = overlap
        report(overlap, duration > 0 ? Motion.keyboard : nil)
    }
}

/// Notification observers, removed with their owner.
private final class KeyboardObservers: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
#endif
