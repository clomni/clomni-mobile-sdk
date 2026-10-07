#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Holds the conversation at the very end of its list while the user is there (operator's iPhone, 2026-10-07): it
/// opens at the end, and history coming in above, a new message, the keyboard and a composer growing to more lines
/// all leave the last message where it was, over the composer with the list's bottom padding under it.
///
/// `ScrollViewProxy.scrollTo` could not do it. It puts an item's edge at the bottom, not the list's end, so the
/// padding stayed under the composer. Called from `onAppear` it ran before the scroll view's first layout, against a
/// LazyVStack's estimated heights, and the list was shown wherever it landed. Nothing answered content growing above
/// the end: a scroll view keeps its offset from the top, so a page of history pushed the end out of sight. And a
/// focused form field was not moved over the keyboard at all (CI, iOS 26). Here the UIScrollView under SwiftUI's
/// ScrollView is moved in the layout pass that changed its content or its height, so the list goes with the
/// keyboard's animation frame by frame, and nothing is estimated: the end is where the content's last view is.
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
    /// The first item's id; when it changes between two layouts, history came in above and the move is instant.
    var first: String?
    /// A form field in the list has the focus: that field stays in sight rather than the end.
    var fieldFocused = false
    /// Shown, at its end.
    private(set) var revealed = false

    private weak var scrollView: UIScrollView?
    /// The bottom of the content (the list's padding included) at its last layout, in the scroll view's coordinates.
    private var end: CGFloat = 0
    /// The scroll view's height at its last layout.
    private var viewport: CGFloat = 0
    private var laidOutFirst: String?
    /// What the user sent, a form or choices: the next growth goes to the end wherever the user was.
    private var forced = false
    /// A soft move to the end is under way: the list is on its way there, not away from it.
    private var movingUntil = Date.distantPast

    nonisolated init() {}

    /// How far the end of the list is under the bottom of what shows, by the last layout.
    private var distance: CGFloat {
        guard let view = scrollView else { return 0 }
        return end - (view.contentOffset.y + height(view) - view.adjustedContentInset.bottom)
    }

    /// The user reads the history, further up than `within`.
    var away: Bool { revealed && distance > Self.within }

    /// The list's scroll view, found from inside its content. A new one (the screen's phase changed) opens at the end.
    func attach(_ view: UIScrollView, end: CGFloat) {
        guard view !== scrollView else { return }
        scrollView = view
        self.end = end
        laidOutFirst = first
        revealed = false
        settle(tries: 10, last: -1)
    }

    /// The content was laid out again; `end` is its new bottom. At the end the list stays there.
    func contentLaidOut(end newEnd: CGFloat) {
        guard let view = scrollView, abs(newEnd - end) > 0.5 else { return }
        let near = distance <= Self.within || (Date() < movingUntil && !view.isTracking)
        let above = first != laidOutFirst
        end = newEnd
        laidOutFirst = first
        guard !revealed || forced || near else { return }
        stick(animated: revealed && !above)
    }

    /// The room for the list changed (the keyboard, the composer): the focused field, or the end, stays in sight.
    func viewportLaidOut(_ height: CGFloat) {
        guard abs(height - viewport) > 0.5 else { return }
        let near = distance <= Self.within
        viewport = height
        guard scrollView != nil else { return }
        if fieldFocused, revealField() { return }
        if !revealed || near { stick(animated: false) }
    }

    /// To the end now, and after the next growth, wherever the user was.
    func follow() {
        forced = true
        stick(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.forced = false }
    }

    /// A form field took the focus: it comes over the bottom, moving the list no more than that.
    func revealFocusedField() {
        _ = revealField()
    }

    private func height(_ view: UIScrollView) -> CGFloat {
        viewport > 0 ? viewport : view.bounds.height
    }

    private func offset(of view: UIScrollView, at y: CGFloat) -> CGFloat {
        let inset = view.adjustedContentInset
        return min(max(y, -inset.top), max(-inset.top, end + inset.bottom - height(view)))
    }

    /// The bottom of the content at the bottom of what shows. Never under the user's finger.
    private func stick(animated: Bool) {
        guard let view = scrollView, !view.isTracking else { return }
        let target = offset(of: view, at: .greatestFiniteMagnitude)
        guard abs(view.contentOffset.y - target) > 0.5 else { return }
        let soft = animated && animates && revealed
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: soft)
        if soft { movingUntil = Date().addingTimeInterval(0.4) }
        // SwiftUI may still settle the content in this pass: a second look once it has.
        if !soft {
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.scrollView, !view.isTracking else { return }
                let again = self.offset(of: view, at: .greatestFiniteMagnitude)
                if abs(view.contentOffset.y - again) > 0.5 {
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: again), animated: false)
                }
            }
        }
    }

    /// Until the end has been drawn its height is an estimate: the list shows once two looks a frame apart agree.
    private func settle(tries: Int, last: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.scrollView != nil, !self.revealed else { return }
            self.stick(animated: false)
            if abs(self.end - last) < 0.5 || tries == 0 {
                self.revealed = true
                self.settled()
            } else {
                self.settle(tries: tries - 1, last: self.end)
            }
        }
    }

    private func revealField() -> Bool {
        guard let view = scrollView, let field = Self.firstResponder(in: view) else { return false }
        let frame = field.convert(field.bounds, to: view)
        let inset = view.adjustedContentInset
        var y = view.contentOffset.y
        let bottom = y + height(view) - inset.bottom
        if frame.maxY + Self.fieldMargin > bottom { y += frame.maxY + Self.fieldMargin - bottom }
        if frame.minY - Self.fieldMargin < y + inset.top { y = frame.minY - Self.fieldMargin - inset.top }
        y = offset(of: view, at: y)
        if abs(y - view.contentOffset.y) > 0.5 {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: false)
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

/// Behind the list's content: finds the scroll view around it and reports where the content ends, each time its size
/// changes. Its first id says whether what came is history above.
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
        // The list is the content's last view: its bottom is the content's end.
        let end = convert(bounds, to: scrollView).maxY
        pin.attach(scrollView, end: end)
        pin.contentLaidOut(end: end)
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
