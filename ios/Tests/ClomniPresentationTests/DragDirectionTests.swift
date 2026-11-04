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
