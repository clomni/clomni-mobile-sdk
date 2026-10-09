#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Holds the conversation at the very end of its list while the user is there (operator's iPhone, 2026-10-07): it
/// opens at the end, and history coming in above, a new message, the keyboard and a composer growing to more lines
/// all leave the last message where it was, over the composer with the list's bottom padding under it.
///
/// `ScrollViewProxy.scrollTo` could not do it: it puts an item's edge at the bottom, not the list's end, and a scroll
/// view keeps its offset from the top, so a page of history pushed the end out of sight. So the UIScrollView under
/// SwiftUI's ScrollView is moved here.
///
/// The end is the content's height. The list is an eager VStack (ChatTranscript), so that height is the list's real
/// one. It was a LazyVStack, whose height is an estimate for the rows it has not drawn, and on iOS 27 the lazy stack
/// itself moves the scroll view's offset while it measures them (WWDC26, session 321). The pin moved the same offset
/// to an end read from a probe behind the last row, and the two fought: on the operator's iPhone (TestFlight 13,
/// iOS 27) the conversation jumped between its end and its first messages, and after a flow's choices it stayed at
/// the top. CI's iOS 26 simulator does not move the offset, so the UI tests passed there.
///
/// Whether the list follows is the user's intent (`pinned`): only the user's own scrolling (more than `within` from
/// the end), VoiceOver or a tapped quote lets go of it. While the user reads above, history coming in over them keeps
/// what they read in place, and nothing moves the list under their finger or while it decelerates.
@MainActor
final class ScrollPin {
    /// Further than this from the end the user reads the history: what comes does not move the list (H2).
    static let within: CGFloat = 120
    /// Over the bottom of what shows, under a focused form field: the rest of its box and 12 (G4).
    static let fieldMargin: CGFloat = 24
    /// The end stands still this many frames in a row: the list is laid out, tracking stops.
    private static let steadyFrames = 30
    /// Tracking never runs longer than this after the last change.
    private static let longestTrack: TimeInterval = 5

    /// The list stands at its end for the first time and can be shown.
    var settled: () -> Void = {}
    /// The list moves softly to its end (off with Reduce Motion).
    var animates = true
    /// A form field in the list has the focus: that field stays in sight rather than the end.
    var fieldFocused = false
    /// Shown, at its end.
    private(set) var revealed = false
    /// The list stays at its end whatever changes; only the user's own scrolling lets go of it.
    private(set) var pinned = true
    /// Where the list's top is against the top of what shows (ChatView's ScrollTopOffset, negative scrolled down):
    /// kept here, not in a state, as it changes every frame of a scroll.
    var listTop: CGFloat = 0

    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    /// The offset is being set here: the change it makes is not news.
    private var adjusting = false
    /// A soft move to the end is under way until then: the offsets it passes through are not the user's.
    private var movingUntil = Date.distantPast
    /// The last item changed since the list last moved to its end.
    private var newLast = false
    private var listed: (first: String?, count: Int, last: String?, loadingAbove: Bool) = (nil, 0, nil, false)
    /// Something came in above the user, who reads further up: the content's height before it and how far the offset
    /// was from the content's bottom, kept when the content grows (in the same layout pass).
    private var above: (height: CGFloat, fromEnd: CGFloat)?
    private var viewport: CGFloat = 0
    private var timer: Timer?
    private var trackUntil = Date.distantPast
    private var steady = 0
    private var lastEnd = CGFloat.nan

    nonisolated init() {}

    /// The user reads the history, further up than `within`.
    var away: Bool { revealed && !pinned }

    /// The list's scroll view, found from inside its content. A new one (the screen's phase changed) opens at the end.
    func attach(_ view: UIScrollView) {
        guard view !== scrollView else { return }
        scrollView = view
        pinned = true
        revealed = false
        observations = [
            view.observe(\.contentSize, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated { self?.contentChanged() }
            },
            view.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrolled() }
            },
        ]
        track()
    }

    /// The content was laid out again (it grew, shrank, or history came in above): at the end, it stays there; above
    /// it, what the user reads stays where it is.
    func contentChanged() {
        if let above, away, let view = scrollView, abs(view.contentSize.height - above.height) > 0.5 {
            self.above = nil
            set(view.contentSize.height - above.fromEnd, in: view)
            return
        }
        guard pinned || !revealed else { return }
        hold()
        track()
    }

    /// The list's items and whether older ones are loading over them, from the screen's body, before its layout: when
    /// they changed, the end is followed until it stands still. A new last item is a new message at the end, which the
    /// list goes to softly; anything else (a page of history above, a row changing its height) moves it at once. With
    /// the user reading above, a change over the first item is kept out of their sight (`above`).
    func list(first: String?, count: Int, last: String?, loadingAbove: Bool) {
        guard (first, count, last, loadingAbove) != listed else { return }
        let overTop = listed.count > 0 && (first != listed.first || loadingAbove != listed.loadingAbove)
        if last != listed.last { newLast = true }
        listed = (first, count, last, loadingAbove)
        if overTop, away, let view = scrollView {
            above = (view.contentSize.height, view.contentSize.height - view.contentOffset.y)
            // Only for this change's layout: should the height not change, it is not news later.
            DispatchQueue.main.async { [weak self] in self?.above = nil }
        }
        if pinned || !revealed { track() }
    }

    /// The room for the list changed (the keyboard, the composer): the focused field, or the end, stays in sight, in
    /// this frame, so that the list moves with the keyboard.
    func viewportLaidOut(_ height: CGFloat) {
        guard abs(height - viewport) > 0.5 else { return }
        viewport = height
        guard scrollView != nil else { return }
        if fieldFocused, revealField() { return }
        guard pinned || !revealed else { return }
        hold(soft: false)
        track()
    }

    /// To the end, softly, and held there.
    func follow() {
        pinned = true
        hold(soft: true)
        track()
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
    /// while it is held (SwiftUI's own, while it lays the list out) is put back by the tracking.
    private func scrolled() {
        guard !adjusting, let view = scrollView else { return }
        if Self.userMoves(view) || (UIAccessibility.isVoiceOverRunning && Date() >= movingUntil), revealed {
            pinned = distance(view) <= Self.within
            return
        }
        if pinned || !revealed { track() }
    }

    /// The user's finger is on the list, or the list still glides from it.
    private static func userMoves(_ view: UIScrollView) -> Bool {
        view.isTracking || view.isDragging || view.isDecelerating
    }

    /// Looks at the end every frame from now until it has stood still for `steadyFrames` frames, putting the list back
    /// at it whenever it is not there. Counted in frames, not time: a slow pass delays the frames, not the count.
    private func track() {
        trackUntil = Date().addingTimeInterval(Self.longestTrack)
        steady = 0
        guard timer == nil, scrollView != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.frame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func frame() {
        guard let view = scrollView, pinned || !revealed, Date() < trackUntil else { return stopTracking() }
        let end = view.contentSize.height
        if abs(end - lastEnd) > 0.5 || abs(view.contentOffset.y - endOffset(view)) > 0.5 { steady = 0 }
        lastEnd = end
        hold()
        steady += 1
        // Shown once it has stood at its end for a few frames; followed on until it has stood still for longer.
        if !revealed, steady >= 3 {
            revealed = true
            settled()
        }
        if steady >= Self.steadyFrames { stopTracking() }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        newLast = false
    }

    /// How far the end of the list is under the bottom of what shows.
    private func distance(_ view: UIScrollView) -> CGFloat {
        view.contentSize.height - (view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom)
    }

    private func clamped(_ y: CGFloat, in view: UIScrollView) -> CGFloat {
        let inset = view.adjustedContentInset
        return min(max(y, -inset.top), max(-inset.top, view.contentSize.height + inset.bottom - view.bounds.height))
    }

    private func endOffset(_ view: UIScrollView) -> CGFloat {
        clamped(.greatestFiniteMagnitude, in: view)
    }

    /// The offset set here, at once, within the content.
    private func set(_ y: CGFloat, in view: UIScrollView) {
        let y = clamped(y, in: view)
        guard abs(y - view.contentOffset.y) > 0.5 else { return }
        adjusting = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: false)
        adjusting = false
    }

    /// The bottom of the list at the bottom of what shows, or the focused form field over it: softly for a new last
    /// item, else at once. Never under the user's finger or while the list glides from it, and not while a soft move
    /// is under way.
    private func hold(soft wanted: Bool? = nil) {
        guard let view = scrollView, !Self.userMoves(view), Date() >= movingUntil else { return }
        if fieldFocused, revealField() { return }
        let target = endOffset(view)
        guard abs(view.contentOffset.y - target) > 0.5 else { return }
        let soft = (wanted ?? newLast) && animates && revealed
        guard soft else { return set(target, in: view) }
        adjusting = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: true)
        adjusting = false
        newLast = false
        movingUntil = Date().addingTimeInterval(0.4)
    }

    private func revealField() -> Bool {
        guard let view = scrollView, let field = Self.firstResponder(in: view) else { return false }
        let frame = field.convert(field.bounds, to: view)
        let inset = view.adjustedContentInset
        var y = view.contentOffset.y
        let bottom = y + view.bounds.height - inset.bottom
        if frame.maxY + Self.fieldMargin > bottom { y += frame.maxY + Self.fieldMargin - bottom }
        if frame.minY - Self.fieldMargin < y + inset.top { y = frame.minY - Self.fieldMargin - inset.top }
        set(y, in: view)
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

/// Behind the list's content: finds the scroll view around it and tells the pin when the content is laid out.
struct ScrollPinContent: UIViewRepresentable {
    let pin: ScrollPin
    let animates: Bool
    let settled: () -> Void

    func makeUIView(context: Context) -> ScrollPinContentView {
        let view = ScrollPinContentView(pin: pin)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: ScrollPinContentView, context: Context) {
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
        pin.attach(scrollView)
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
