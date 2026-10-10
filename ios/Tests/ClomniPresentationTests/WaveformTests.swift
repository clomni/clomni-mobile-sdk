import Foundation
import XCTest
@testable import ClomniPresentation

/// The waveform's numbers: the same expectations as Android's WaveformTest.
final class WaveformTests: XCTestCase {
    private let half = Waveform.floor + (1 - Waveform.floor) * 0.5

    private func assertBars(_ actual: [Double], _ expected: [Double], line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, line: line)
        for (got, want) in zip(actual, expected) { XCTAssertEqual(got, want, accuracy: 0.0001, line: line) }
    }

    func testLoudnessToLevels() {
        XCTAssertEqual(Waveform.level(decibels: 0), 1)
        XCTAssertEqual(Waveform.level(decibels: -25), 0.5)
        XCTAssertEqual(Waveform.level(decibels: -50), 0)
        XCTAssertEqual(Waveform.level(decibels: -160), 0)
        XCTAssertEqual(Waveform.level(decibels: 3), 1)
    }

    func testEncodeTakesEachShareLoudest() {
        let levels = (0..<640).map { $0 % 10 == 3 ? 0.9 : 0.1 }
        XCTAssertEqual(Waveform.encode(levels), Array(repeating: 90, count: 64))
        let word = (0..<6_000).map { $0 > 5_990 ? 1.0 : 0 }
        XCTAssertEqual(Waveform.encode(word).last, 100)
        XCTAssertEqual(Waveform.encode(word).first, 0)
    }

    func testEncodeStretchesAShortRecording() {
        let stretched = Waveform.encode([0, 0.5, 1])
        XCTAssertEqual(stretched.count, 64)
        XCTAssertEqual(Set(stretched), [0, 50, 100])
        XCTAssertEqual(Waveform.encode([]), [])
        XCTAssertEqual(Waveform.encode([4, -1], points: 2), [100, 0])
    }

    func testBarsToDraw() {
        XCTAssertEqual(Waveform.bars(nil, count: 5), Array(repeating: Waveform.plain, count: 5))
        XCTAssertEqual(Waveform.bars([], count: 3), Array(repeating: Waveform.plain, count: 3))
        XCTAssertEqual(Waveform.bars([10], count: 0), [])
        assertBars(Waveform.bars([0, 100, 50, 0], count: 2), [1, half])
        assertBars(Waveform.bars([0, 0], count: 2), [Waveform.floor, Waveform.floor])
        let floor = Waveform.floor
        assertBars(Waveform.bars([0, 100, 0], count: 6), [floor, floor, 1, 1, floor, floor])
        assertBars(Waveform.bars([400], count: 1), [1])
    }

    func testLiveShowsTheNewestAtTheEnd() {
        XCTAssertEqual(Waveform.live([], count: 4), Array(repeating: Waveform.floor, count: 4))
        assertBars(Waveform.live([1, 0, 1, 0.5, 1], count: 3), [1, half, 1])
        assertBars(Waveform.live([1], count: 2), [Waveform.floor, 1])
        XCTAssertEqual(Waveform.live([1], count: 0), [])
    }
}
