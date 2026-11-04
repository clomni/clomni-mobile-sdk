import Foundation
import XCTest
@testable import ClomniPresentation

/// CM-342: a drag on a bubble is the list's unless it goes more across than up or down.
final class DragDirectionTests: XCTestCase {
    func testAcrossOrUpAndDown() {
        XCTAssertTrue(DragDirection.sideways(dx: 10, dy: 3, rightOnly: true))
        XCTAssertFalse(DragDirection.sideways(dx: -10, dy: 3, rightOnly: true), "the swipe to answer goes right only")
        XCTAssertTrue(DragDirection.sideways(dx: -10, dy: 3, rightOnly: false), "the waveform's goes either way")
        XCTAssertFalse(DragDirection.sideways(dx: 6, dy: -8, rightOnly: false), "up, a little to the side: the list's")
        XCTAssertFalse(DragDirection.sideways(dx: 5, dy: 5, rightOnly: false), "a diagonal is the list's")
    }

    func testVerticalOnceTheFingerHasMoved() {
        XCTAssertFalse(DragDirection.vertical(CGSize(width: 0, height: 3)), "under the slop nothing is decided: a tap")
        XCTAssertTrue(DragDirection.vertical(CGSize(width: 1, height: 4)))
        XCTAssertTrue(DragDirection.vertical(CGSize(width: -3, height: -20)))
        XCTAssertFalse(DragDirection.vertical(CGSize(width: 30, height: 5)))
    }
}

/// CM-346 § 5.3 (TestFlight #21: «öz mesajına yanıt vermək olmur»): the user's own messages stand at the right edge,
/// where a drag to the right has little room; theirs answer at 40 pt of finger, an operator's at 80 as before.
final class ReplySwipeTests: XCTestCase {
    func testTheUsersOwnMessageAnswersAtAShorterDrag() {
        XCTAssertTrue(ReplySwipe.answers(56, outgoing: true), "60 pt from the edge, dragged to it: answered")
        XCTAssertFalse(ReplySwipe.answers(56, outgoing: false), "an operator's needs more")
        XCTAssertTrue(ReplySwipe.answers(80, outgoing: false))
        XCTAssertFalse(ReplySwipe.answers(38, outgoing: true), "a little: not yet")
        XCTAssertTrue(ReplySwipe.answers(40, outgoing: true))
        XCTAssertFalse(ReplySwipe.answers(-80, outgoing: true), "to the left: never")
        XCTAssertEqual(ReplySwipe.pulled(40, outgoing: true), 28, accuracy: 0.001, "the bubble follows at 70%")
        XCTAssertEqual(ReplySwipe.pulled(500, outgoing: true), ReplySwipe.threshold(outgoing: true) + 24, "and stops")
    }
}
