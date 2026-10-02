import XCTest
@testable import ClomniPresentation

/// The swipe back's rules, apart from SwiftUI: where it starts, how far it goes, when it completes.
final class BackSwipeTests: XCTestCase {
    private let width = 390.0

    func testItStartsOnlyAtTheEdgeAndSideways() {
        XCTAssertTrue(BackSwipe.begins(atX: 0, dx: 12, dy: 2))
        XCTAssertTrue(BackSwipe.begins(atX: 20, dx: 12, dy: 2), "the 20 pt zone")
        XCTAssertFalse(BackSwipe.begins(atX: 21, dx: 12, dy: 2), "past the zone: the screen's own drag")
        XCTAssertFalse(BackSwipe.begins(atX: 150, dx: 80, dy: 0), "mid-screen, e.g. a horizontal list")
        XCTAssertFalse(BackSwipe.begins(atX: 5, dx: 4, dy: 12), "more up or down: the transcript scrolls")
        XCTAssertFalse(BackSwipe.begins(atX: 5, dx: -12, dy: 0), "towards the edge")
    }

    func testTheScreenFollowsTheFinger() {
        XCTAssertEqual(BackSwipe.offset(translation: 120, width: width), 120)
        XCTAssertEqual(BackSwipe.offset(translation: -40, width: width), 0, "not left of where it was")
        XCTAssertEqual(BackSwipe.offset(translation: 500, width: width), width, "not past the edge")
    }

    func testPastAThirdOrAFlickGoesBack() {
        XCTAssertTrue(BackSwipe.completes(translation: 131, predictedEnd: 131, width: width), "past 130, a third")
        XCTAssertFalse(BackSwipe.completes(translation: 129, predictedEnd: 140, width: width), "short and slow: stays")
        XCTAssertTrue(BackSwipe.completes(translation: 60, predictedEnd: 250, width: width), "a flick")
        XCTAssertFalse(BackSwipe.completes(translation: 60, predictedEnd: 230, width: width), "not quite a flick")
        XCTAssertFalse(BackSwipe.completes(translation: 200, predictedEnd: 40, width: width),
                       "past a third, then flicked back: it returns")
        XCTAssertTrue(BackSwipe.completes(translation: 200, predictedEnd: 190, width: width), "past a third, let go")
        XCTAssertFalse(BackSwipe.completes(translation: 0, predictedEnd: 300, width: width), "never moved")
        XCTAssertFalse(BackSwipe.completes(translation: 200, predictedEnd: 300, width: 0), "no width")
    }

    func testHomeShowsBehindWithParallax() {
        XCTAssertEqual(BackSwipe.behindOffset(offset: 0, width: width), -117, accuracy: 0.001, "30% to the left")
        XCTAssertEqual(BackSwipe.behindOffset(offset: width / 2, width: width), -58.5, accuracy: 0.001)
        XCTAssertEqual(BackSwipe.behindOffset(offset: width, width: width), 0, accuracy: 0.001, "in place once gone")
        XCTAssertEqual(BackSwipe.behindOffset(offset: 50, width: 0), 0)
    }
}
