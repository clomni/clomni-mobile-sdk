#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// How much of a screen the keyboard covers, measured by UIKit's keyboard layout guide in that screen's coordinates
/// (operator, 2026-10-07, H1). SwiftUI's keyboard avoidance did not reach the conversation inside the
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

/// Where the keyboard's top is comes from UIKit's keyboard layout guide, which follows every keyboard as it is drawn:
/// the letters with or without their suggestions, the emoji keyboard and its search field, a hardware keyboard's bar.
/// The keyboard's notifications only say how long its move takes, to follow it with the same animation. Their frames
/// alone left a ~40 pt band between the composer and the emoji keyboard on the operator's iPhone (2026-10-09).
final class KeyboardProbeView: UIView {
    var report: (CGFloat, Animation?) -> Void = { _, _ in }
    /// Pinned to the top of the keyboard layout guide: its frame is where the keyboard begins, in this view.
    private let keyboardTop = UIView()
    private var reported: CGFloat = 0
    /// A docked keyboard is up (its notifications say so): only then does anything cover this view.
    private var keyboardUp = false
    /// The keyboard is moving (its notification said so) until then: what is measured meanwhile follows its animation.
    private var movingUntil = Date.distantPast
    private let observers = KeyboardObservers()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        keyboardTop.isHidden = true
        keyboardTop.isUserInteractionEnabled = false
        keyboardTop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardTop)
        // Undocked or floating (iPad), the guide stays at the bottom: nothing is covered.
        keyboardLayoutGuide.followsUndockedKeyboard = false
        NSLayoutConstraint.activate([
            keyboardTop.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardTop.widthAnchor.constraint(equalToConstant: 1),
            keyboardTop.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            keyboardTop.heightAnchor.constraint(equalToConstant: 1),
        ])
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification,
                     UIResponder.keyboardDidChangeFrameNotification] {
            observers.tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                    .doubleValue ?? 0
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let hides = note.name == UIResponder.keyboardWillHideNotification
                let will = note.name != UIResponder.keyboardDidChangeFrameNotification
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let bottom = self.window?.screen.bounds.maxY ?? end?.maxY ?? 0
                    self.keyboardUp = !hides && (end.map { $0.height > 0 && $0.maxY >= bottom - 1 } ?? false)
                    if will, duration > 0 { self.movingUntil = Date().addingTimeInterval(duration + 0.1) }
                    // The guide moves in the keyboard's own layout pass; measured once it has.
                    self.setNeedsLayout()
                    DispatchQueue.main.async { [weak self] in self?.measure() }
                }
            })
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    // The keyboard's guide moved, or the sheet resized or turned: measured again, after this layout pass (SwiftUI's
    // state is not changed in the middle of one).
    override func layoutSubviews() {
        super.layoutSubviews()
        DispatchQueue.main.async { [weak self] in self?.measure() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.measure() }
    }

    /// How far the keyboard's top is above this view's bottom; 0 while it is down or floats.
    private func measure() {
        guard window != nil else { return }
        layoutIfNeeded()
        let overlap = keyboardUp ? max(0, bounds.maxY - keyboardTop.frame.minY) : 0
        guard abs(overlap - reported) > 0.5 else { return }
        reported = overlap
        report(overlap, Date() < movingUntil ? Motion.keyboard : nil)
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
