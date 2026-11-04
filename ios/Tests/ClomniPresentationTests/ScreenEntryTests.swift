import Foundation
import XCTest
@testable import ClomniPresentation

/// CM-346 § 5.1 (TestFlight #21): a screen coming into view shows the spinner for at least 350 ms and until its data
/// is there, cached or not; then its content, fading in over 150 ms. Time is the test's (ManualTimer).
@MainActor
final class ScreenEntryTests: XCTestCase {
    private let timer = ManualTimer()

    private func entry() -> ScreenEntry {
        let timer = timer
        return ScreenEntry(sleep: { try await timer.sleep($0) })
    }

    /// Lets the wait that is running now end, and waits for what it does.
    private func pass(_ entry: ScreenEntry) async {
        let waiting = entry.waiting
        await timer.waitForSleepers(1)
        await timer.fire()
        await waiting?.value
    }

    func testTheSpinnerStaysTheMinimumWithTheDataThere() async {
        let screen = entry()
        XCTAssertFalse(screen.showsContent(ready: true), "cached: the spinner all the same")
        await pass(screen)
        XCTAssertTrue(screen.showsContent(ready: true), "after the minimum")
    }

    func testTheSpinnerStaysUntilTheDataComes() async {
        let screen = entry()
        await pass(screen)
        XCTAssertFalse(screen.showsContent(ready: false), "the minimum passed, nothing to show yet")
        XCTAssertTrue(screen.showsContent(ready: true), "the data came")
    }

    func testComingIntoViewAgainStartsOver() async {
        var changes = 0
        let screen = entry()
        screen.onChange = { changes += 1 }
        await pass(screen)
        XCTAssertTrue(screen.showsContent(ready: true))
        screen.start()
        XCTAssertFalse(screen.showsContent(ready: true), "its tab chosen again: the spinner first")
        await pass(screen)
        XCTAssertTrue(screen.showsContent(ready: true))
        XCTAssertEqual(changes, 3)
    }

    func testTheNumbers() async {
        XCTAssertEqual(ScreenEntry.minimum, 0.35)
        XCTAssertEqual(ScreenEntry.fadeIn, 0.15)
        let asked = Asked()
        let timer = timer
        let screen = ScreenEntry(minimum: 1.5, sleep: { seconds in
            await asked.add(seconds)
            try await timer.sleep(seconds)
        })
        await pass(screen)
        let values = await asked.values
        XCTAssertEqual(values, [1.5], "the UI tests' longer hold")
    }
}

private actor Asked {
    private(set) var values: [TimeInterval] = []
    func add(_ value: TimeInterval) { values.append(value) }
}
