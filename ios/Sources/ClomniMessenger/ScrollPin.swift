#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Holds the conversation at the very end of its list while the user is there (operator's iPhone, 2026-10-07): it
/// opens at the end, and history coming in above, a new message, the keyboard and a composer growing to more lines
/// all leave the last message where it was, over the composer with the list's bottom padding under it.
///
/// `ScrollViewProxy.scrollTo` could not do it. It puts an item's edge at the bottom, not the list's end, so the
/// padding stayed under the composer. Called from `onAppear` it ran before the scroll view's first layout, against a
/// LazyVStack's estimated heights. Nothing answered content growing above the end: a scroll view keeps its offset
/// from the top, so a page of history pushed the end out of sight. So the UIScrollView under SwiftUI's ScrollView is
/// moved here, whenever its content, its height or its offset changes.
///
/// Whether the list follows is the user's intent, kept in `pinned`, not worked out again from the geometry at each
/// change: on CI (iOS 26) the list stood near the top of the oldest page after the history came, because the
/// earlier version asked at every layout whether the list was still near its end, measured against the previous
/// layout, and once an offset that SwiftUI set on its own between two layouts made the answer "no", the list was let
/// go for good. Now only the user lets go: dragging or flinging it more than `within` from the end, VoiceOver
/// scrolling it, or a tap on a quote. Every other move away from the end while pinned is put back.
@MainActor
final class ScrollPin {
    /// Further than this from the end the user reads the history: what comes does not move the list (H2).
    static let within: CGFloat = 120
    /// Over the bottom of what shows, under a focused form field: the rest of its box and 12 (G4).
    static let fieldMargin: CGFloat = 24

    /// The list stands at its end for the first time and can be shown.
    var settled: () -> Void = {}
    /// The list moves softly to its end (off with Reduce Motion).
    var animates = true
    /// The first item's id; when it changes, history came in above and the move is instant.
    var first: String?
    /// A form field in the list has the focus: that field stays in sight rather than the end.
    var fieldFocused = false
    /// Shown, at its end.
    private(set) var revealed = false
    /// The list stays at its end whatever changes; only the user's own scrolling lets go of it.
    private(set) var pinned = true

    private weak var scrollView: UIScrollView?
    /// The list itself, inside the scroll view: its bottom is the end.
    private weak var content: UIView?
    private var observations: [NSKeyValueObservation] = []
    private var heldFirst: String?
    /// The offset is being set here: the change it makes is not news.
    private var adjusting = false
    /// A soft move to the end is under way until then: the offsets it passes through are not the user's.
    private var movingUntil = Date.distantPast
    /// A move back to the end is already on its way (once per turn of the run loop).
    private var holdQueued = false
    private var viewport: CGFloat = 0

    nonisolated init() {}

    /// The user reads the history, further up than `within`.
    var away: Bool { revealed && !pinned }

    /// The list's scroll view, found from inside its content. A new one (the screen's phase changed) opens at the end.
    func attach(_ view: UIScrollView, content: UIView) {
        self.content = content
        guard view !== scrollView else { return }
        scrollView = view
        pinned = true
        revealed = false
        heldFirst = first
        observations = [
            view.observe(\.contentSize, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated { self?.contentChanged() }
            },
            view.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrolled() }
            },
        ]
        settle(tries: 20, last: -1)
    }

    /// The content was laid out again (it grew, shrank, or history came in above): at the end, it stays there.
    func contentChanged() {
        let above = first != heldFirst
        heldFirst = first
        guard pinned || !revealed else { return }
        hold(animated: revealed && !above)
    }

    /// The room for the list changed (the keyboard, the composer): the focused field, or the end, stays in sight.
    func viewportLaidOut(_ height: CGFloat) {
        guard abs(height - viewport) > 0.5 else { return }
        viewport = height
        guard scrollView != nil else { return }
        if fieldFocused, revealField() { return }
        if pinned || !revealed { hold(animated: false) }
    }

    /// To the end now, softly, and held there.
    func follow() {
        pinned = true
        hold(animated: true)
    }

    /// The list goes somewhere else on purpose (a tapped quote): it is not held at the end.
    func release() {
        pinned = false
    }

    /// A form field took the focus: it comes over the bottom, moving the list no more than that.
    func revealFocusedField() {
        _ = revealField()
    }

    /// The offset changed. The user's own scrolling decides whether the list is held; any other move away from the end
    /// while it is held (SwiftUI's own, while it lays the list out) is put back.
    private func scrolled() {
        guard !adjusting, let view = scrollView else { return }
        let user = view.isTracking || view.isDragging || view.isDecelerating || UIAccessibility.isVoiceOverRunning
        if user, revealed {
            pinned = distance(view) <= Self.within
            return
        }
        guard pinned, Date() >= movingUntil, abs(view.contentOffset.y - endOffset(view)) > 0.5 else { return }
        queueHold()
    }

    private func queueHold() {
        guard !holdQueued else { return }
        holdQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.holdQueued = false
            if self.pinned || !self.revealed { self.hold(animated: false) }
        }
    }

    /// The bottom of the list, in the scroll view's content; not past the content's size while SwiftUI has yet to set
    /// it (its own change brings the list there next).
    private func end(_ view: UIScrollView) -> CGFloat {
        guard let content, content.isDescendant(of: view) else { return view.contentSize.height }
        let bottom = content.convert(content.bounds, to: view).maxY
        return view.contentSize.height > 0 ? min(bottom, view.contentSize.height) : bottom
    }

    /// How far the end of the list is under the bottom of what shows.
    private func distance(_ view: UIScrollView) -> CGFloat {
        end(view) - (view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom)
    }

    private func clamped(_ y: CGFloat, in view: UIScrollView) -> CGFloat {
        let inset = view.adjustedContentInset
        return min(max(y, -inset.top), max(-inset.top, end(view) + inset.bottom - view.bounds.height))
    }

    private func endOffset(_ view: UIScrollView) -> CGFloat {
        clamped(.greatestFiniteMagnitude, in: view)
    }

    /// The bottom of the list at the bottom of what shows, or the focused form field over it. Never under the user's
    /// finger.
    private func hold(animated: Bool) {
        guard let view = scrollView, !view.isTracking else { return }
        if fieldFocused, revealField() { return }
        let target = endOffset(view)
        guard abs(view.contentOffset.y - target) > 0.5 else { return }
        let soft = animated && animates && revealed
        adjusting = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: soft)
        adjusting = false
        guard soft else { return }
        // The soft move's frames are not the user's; once it is over, the end is checked again.
        movingUntil = Date().addingTimeInterval(0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.pinned else { return }
            self.hold(animated: false)
        }
    }

    /// Until the end has been drawn its height is an estimate: the list shows once two looks a frame apart agree.
    private func settle(tries: Int, last: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, let view = self.scrollView, !self.revealed else { return }
            self.hold(animated: false)
            let now = self.end(view)
            if (abs(now - last) < 0.5 && abs(view.contentOffset.y - self.endOffset(view)) < 0.5) || tries == 0 {
                self.revealed = true
                self.settled()
            } else {
                self.settle(tries: tries - 1, last: now)
            }
        }
    }

    private func revealField() -> Bool {
        guard let view = scrollView, let field = Self.firstResponder(in: view) else { return false }
        let frame = field.convert(field.bounds, to: view)
        let inset = view.adjustedContentInset
        var y = view.contentOffset.y
        let bottom = y + view.bounds.height - inset.bottom
        if frame.maxY + Self.fieldMargin > bottom { y += frame.maxY + Self.fieldMargin - bottom }
        if frame.minY - Self.fieldMargin < y + inset.top { y = frame.minY - Self.fieldMargin - inset.top }
        y = clamped(y, in: view)
        if abs(y - view.contentOffset.y) > 0.5 {
            adjusting = true
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: false)
            adjusting = false
        }
        return true
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}

/// Behind the list's content: finds the scroll view around it and stands for the list's end; reports each time the
/// list's size changes. Its first id says whether what came is history above.
struct ScrollPinContent: UIViewRepresentable {
    let pin: ScrollPin
    let first: String?
    let animates: Bool
    let settled: () -> Void

    func makeUIView(context: Context) -> ScrollPinContentView {
        let view = ScrollPinContentView(pin: pin)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: ScrollPinContentView, context: Context) {
        pin.first = first
        pin.animates = animates
        pin.settled = settled
    }
}

final class ScrollPinContentView: UIView {
    private let pin: ScrollPin

    init(pin: ScrollPin) {
        self.pin = pin
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    private func report() {
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scrollView = ancestor as? UIScrollView else { return }
        pin.attach(scrollView, content: self)
        pin.contentChanged()
    }
}

/// Behind the scroll view: reports its height as it changes, frame by frame while the keyboard moves.
struct ScrollPinViewport: UIViewRepresentable {
    let pin: ScrollPin

    func makeUIView(context: Context) -> ScrollPinViewportView {
        ScrollPinViewportView(pin: pin)
    }

    func updateUIView(_ view: ScrollPinViewportView, context: Context) {}
}

final class ScrollPinViewportView: UIView {
    private let pin: ScrollPin

    init(pin: ScrollPin) {
        self.pin = pin
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pin.viewportLaidOut(bounds.height)
    }
}
#endif
