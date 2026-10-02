import Foundation
import XCTest
@testable import ClomniPresentation

/// DESIGN-PASS 5: the indicator shows after 300 ms of loading and then stays at least 400 ms. Time is the test's
/// (ManualTimer): no real waiting.
@MainActor
final class SpinnerTimingTests: XCTestCase {
    private let timer = ManualTimer()

    private func timing() -> SpinnerTiming {
        let timer = timer
        return SpinnerTiming(sleep: { try await timer.sleep($0) })
    }

    /// Lets the wait that is running now end, and waits for what it does.
    private func pass(_ timing: SpinnerTiming) async {
        let waiting = timing.waiting
        await timer.waitForSleepers(1)
        await timer.fire()
        await waiting?.value
    }

    func testAQuickLoadShowsNothing() async {
        let spinner = timing()
        spinner.set(loading: true)
        await timer.waitForSleepers(1)
        spinner.set(loading: false)
        await timer.fire()
        await spinner.waiting?.value
        XCTAssertFalse(spinner.visible, "done within 300 ms: no flash")
    }

    func testASlowLoadShowsAfterTheDelayAndStaysTheMinimum() async {
        var changes = 0
        let spinner = timing()
        spinner.onChange = { changes += 1 }
        spinner.set(loading: true)
        XCTAssertFalse(spinner.visible, "not at once")
        await pass(spinner)
        XCTAssertTrue(spinner.visible, "300 ms later")

        // Loading ends at once: it stays until 400 ms have passed.
        spinner.set(loading: false)
        XCTAssertTrue(spinner.visible, "no blink")
        await pass(spinner)
        XCTAssertFalse(spinner.visible)
        XCTAssertEqual(changes, 2)
    }

    func testALongLoadHidesWhenItEnds() async {
        let spinner = timing()
        spinner.set(loading: true)
        await pass(spinner)
        await pass(spinner)
        XCTAssertTrue(spinner.visible, "the minimum passed, still loading")
        spinner.set(loading: false)
        XCTAssertFalse(spinner.visible, "at once")
    }

    func testLoadingAgainWhileShownKeepsIt() async {
        let spinner = timing()
        spinner.set(loading: true)
        await pass(spinner)
        spinner.set(loading: false)
        spinner.set(loading: true)
        await pass(spinner)
        XCTAssertTrue(spinner.visible, "loading again before the minimum ended")
        spinner.set(loading: false)
        XCTAssertFalse(spinner.visible)
    }

    func testTheDelayAndTheMinimum() async {
        XCTAssertEqual(SpinnerTiming.delay, 0.3)
        XCTAssertEqual(SpinnerTiming.minimum, 0.4)
        let recorded = Recorded()
        let timer = timer
        let spinner = SpinnerTiming(sleep: { seconds in
            await recorded.add(seconds)
            try await timer.sleep(seconds)
        })
        spinner.set(loading: true)
        await pass(spinner)
        await timer.waitForSleepers(1)
        let asked = await recorded.values
        XCTAssertEqual(asked, [0.3, 0.4])
    }
}

final class LoadingTextTests: XCTestCase {
    /// The indicator's VoiceOver label, the server's `loading` key when the config has it.
    func testLoadingText() {
        XCTAssertEqual(["az", "en", "ru"].map { ClomniStrings(language: $0)[.loading] }, ["Yüklənir", "Loading", "Загрузка"])
        XCTAssertEqual(ClomniStrings.Key.loading.rawValue, "loading")
        XCTAssertEqual(ClomniStrings(language: "az", overrides: ["loading": "Gözləyin"])[.loading], "Gözləyin")
    }
}

private actor Recorded {
    private(set) var values: [TimeInterval] = []
    func add(_ value: TimeInterval) { values.append(value) }
}
