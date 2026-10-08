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
/// `ScrollViewProxy.scrollTo` could not do it: it puts an item's edge at the bottom, not the list's end; called from
/// `onAppear` it ran before the first layout, against a LazyVStack's estimated heights; and a scroll view keeps its
/// offset from the top, so a page of history pushed the end out of sight. So the UIScrollView under SwiftUI's
/// ScrollView is moved here.
///
/// Whether the list follows is the user's intent (`pinned`): only the user's own scrolling (more than `within` from
/// the end), VoiceOver or a tapped quote lets go of it.
///
/// Where the end is, is read from the last row as UIKit has placed it, frame after frame, until it has stopped moving
/// (`track`). SwiftUI does not place the rows in the pass that tells of a change: after a page of history above, it
/// set the content's size first and moved the rows below later, on CI after a slow pass, with no change of size that
/// KVO or a probe's layout would report. Fixed windows of looks (0-300 ms) missed that move on CI, more often the
/// slower the simulator (CM-087, 3 of 3 on aa63422), and the list stayed where the history had pushed it.
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

    private weak var scrollView: UIScrollView?
    /// Behind the list's last row (ScrollPinLastRow): where the list really ends, as drawn.
    weak var lastRow: UIView? {
        didSet { if lastRow !== oldValue { track() } }
    }
    private var observations: [NSKeyValueObservation] = []
    /// The offset is being set here: the change it makes is not news.
    private var adjusting = false
    /// A soft move to the end is under way until then: the offsets it passes through are not the user's.
    private var movingUntil = Date.distantPast
    /// The last item changed since the list last moved to its end.
    private var newLast = false
    private var listed: (first: String?, count: Int, last: String?) = (nil, 0, nil)
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

    /// The content was laid out again (it grew, shrank, or history came in above): at the end, it stays there.
    func contentChanged() {
        guard pinned || !revealed else { return }
        hold()
        track()
    }

    /// The list's items as SwiftUI updates them, before its layout: when they changed, the end is followed until it
    /// stands still. A new last item is a new message at the end, which the list goes to softly; anything else (a page
    /// of history above, a row changing its height) moves it at once.
    func list(first: String?, count: Int, last: String?) {
        guard (first, count, last) != listed else { return }
        if last != listed.last { newLast = true }
        listed = (first, count, last)
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
        let user = view.isTracking || view.isDragging || view.isDecelerating || UIAccessibility.isVoiceOverRunning
        if user, revealed {
            pinned = distance(view) <= Self.within
            return
        }
        if pinned || !revealed { track() }
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
        let end = end(view)
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

    /// The bottom of the list, in the scroll view's content: under its last row as drawn; while that row is not drawn
    /// (far from it), the content's size, which brings the list where the row gets drawn.
    private func end(_ view: UIScrollView) -> CGFloat {
        guard let row = lastRow, row.window != nil, row.isDescendant(of: view) else { return view.contentSize.height }
        return row.convert(row.bounds, to: view).maxY + ChatTranscript.bottomPadding
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

    /// The bottom of the list at the bottom of what shows, or the focused form field over it: softly for a new last
    /// item, else at once. Never under the user's finger, and not while a soft move is under way.
    private func hold(soft wanted: Bool? = nil) {
        guard let view = scrollView, !view.isTracking, Date() >= movingUntil else { return }
        if fieldFocused, revealField() { return }
        let target = endOffset(view)
        guard abs(view.contentOffset.y - target) > 0.5 else { return }
        let soft = (wanted ?? newLast) && animates && revealed
        adjusting = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: soft)
        adjusting = false
        if soft {
            newLast = false
            movingUntil = Date().addingTimeInterval(0.4)
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

/// Behind the list's content: finds the scroll view around it; tells the pin when the list changes, and whether its last
/// item is a new one.
struct ScrollPinContent: UIViewRepresentable {
    let pin: ScrollPin
    let items: [ChatItem]
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
        pin.list(first: items.first?.id, count: items.count, last: items.last?.id)
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

/// Behind the list's last row: where the list really ends. Reports when it comes, goes or changes its height.
struct ScrollPinLastRow: UIViewRepresentable {
    let pin: ScrollPin

    func makeUIView(context: Context) -> ScrollPinLastRowView {
        ScrollPinLastRowView(pin: pin)
    }

    func updateUIView(_ view: ScrollPinLastRowView, context: Context) {}
}

final class ScrollPinLastRowView: UIView {
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
        if window != nil {
            pin.lastRow = self
        } else if pin.lastRow === self {
            pin.lastRow = nil
        }
        pin.contentChanged()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
