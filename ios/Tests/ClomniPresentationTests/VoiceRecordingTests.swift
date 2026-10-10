import Foundation
import XCTest
@testable import ClomniPresentation

/// The microphone button's rules, without a microphone (the same cases as Android's VoiceRecordingTest).
final class VoiceRecordingTests: XCTestCase {
    private var voice = VoiceRecording(maxMs: 300_000)

    private func record(for ms: Int, level: Double = 0.5) {
        var at = 0
        while at < ms {
            at += 50
            _ = voice.tick(elapsedMs: at, level: level)
        }
    }

    func testHoldThenLetGoSends() {
        XCTAssertEqual(voice.press(.granted), [.start])
        XCTAssertEqual(voice.state, .holding(elapsedMs: 0, cancel: 0, lock: 0))
        record(for: 2_000)
        XCTAssertEqual(voice.state, .holding(elapsedMs: 2_000, cancel: 0, lock: 0))
        guard case .send(let waveform)? = voice.release().first else { return XCTFail() }
        XCTAssertEqual(waveform.count, Waveform.points)
        XCTAssertEqual(waveform.first, 50)
        XCTAssertEqual(voice.state, .idle)
    }

    func testAShortPressIsNoMessage() {
        _ = voice.press(.granted)
        record(for: 650)
        XCTAssertEqual(voice.release(), [.discard(animated: false), .holdHint])
        _ = voice.press(.granted)
        record(for: VoiceRecording.minMs)
        guard case .send? = voice.release().first else { return XCTFail("from minMs it is one") }
    }

    func testSlidingLeftThrowsItAway() {
        _ = voice.press(.granted)
        record(for: 1_000)
        XCTAssertEqual(voice.drag(dx: -60, dy: 4), [])
        XCTAssertEqual(voice.state, .holding(elapsedMs: 1_000, cancel: 0.5, lock: 0))
        XCTAssertEqual(voice.drag(dx: -VoiceRecording.cancelDistance, dy: 0), [.discard(animated: true)])
        XCTAssertEqual(voice.release(), [], "the finger coming up afterwards sends nothing")
    }

    func testSlidingUpLocksThenStopListenSend() {
        _ = voice.press(.granted)
        record(for: 1_000)
        _ = voice.drag(dx: 0, dy: -45)
        XCTAssertEqual(voice.state, .holding(elapsedMs: 1_000, cancel: 0, lock: 0.5))
        XCTAssertEqual(voice.drag(dx: -10, dy: -VoiceRecording.lockDistance), [.locked])
        XCTAssertEqual(voice.release(), [], "the hand can go")
        record(for: 3_000)
        XCTAssertEqual(voice.state, .locked(elapsedMs: 3_000))
        XCTAssertEqual(voice.stop(), [.stop])
        XCTAssertEqual(voice.state, .review(durationMs: 3_000))
        XCTAssertEqual(voice.tick(elapsedMs: 3_050, level: 1), [])
        guard case .send? = voice.send().first else { return XCTFail() }
        XCTAssertEqual(voice.state, .idle)
    }

    func testDeleteWhileLockedOrListening() {
        _ = voice.press(.granted)
        _ = voice.drag(dx: 0, dy: -200)
        XCTAssertEqual(voice.delete(), [.discard(animated: true)])
        _ = voice.press(.granted)
        _ = voice.drag(dx: 0, dy: -200)
        record(for: 1_000)
        _ = voice.stop()
        XCTAssertEqual(voice.delete(), [.discard(animated: true)])
        XCTAssertEqual(voice.state, .idle)
    }

    func testTheLimitStopsItForReview() {
        var short = VoiceRecording(maxMs: 1_000)
        _ = short.press(.granted)
        XCTAssertEqual(short.tick(elapsedMs: 950, level: 0.2), [])
        XCTAssertEqual(short.tick(elapsedMs: 1_000, level: 0.2), [.stop])
        XCTAssertEqual(short.state, .review(durationMs: 1_000))
        XCTAssertEqual(short.release(), [])
        guard case .send? = short.send().first else { return XCTFail() }
    }

    func testPermission() {
        XCTAssertEqual(voice.press(.undecided), [.askPermission])
        XCTAssertEqual(voice.state, .idle)
        XCTAssertEqual(voice.press(.denied), [.permissionDenied])
        XCTAssertEqual(voice.pressLocked(.denied), [.permissionDenied])
        XCTAssertEqual(voice.state, .idle)
    }

    func testVoiceOverRecordsLocked() {
        XCTAssertEqual(voice.pressLocked(.granted), [.start])
        XCTAssertEqual(voice.state, .locked(elapsedMs: 0))
    }

    func testWhatDoesNotApplyIsIgnored() {
        XCTAssertEqual(voice.drag(dx: -500, dy: -500), [])
        XCTAssertEqual(voice.release(), [])
        XCTAssertEqual(voice.stop(), [])
        XCTAssertEqual(voice.delete(), [])
        XCTAssertEqual(voice.send(), [])
        XCTAssertEqual(voice.tick(elapsedMs: 100, level: 1), [])
        XCTAssertEqual(voice.fail(), [])
        _ = voice.press(.granted)
        XCTAssertEqual(voice.press(.granted), [], "a second finger")
        XCTAssertEqual(voice.fail(), [.discard(animated: false)])
        _ = voice.press(.granted)
        XCTAssertEqual(voice.levels, [])
        _ = voice.tick(elapsedMs: 50, level: 2)
        XCTAssertEqual(voice.levels, [1], "clamped")
    }

    func testBeforeTheMicrophoneComesTheClockRunsWithoutBars() {
        var voice = VoiceRecording(maxMs: 300_000)
        _ = voice.press(.granted)
        XCTAssertEqual(voice.tick(elapsedMs: 800, level: nil), [])
        XCTAssertEqual(voice.state, .holding(elapsedMs: 800, cancel: 0, lock: 0))
        XCTAssertEqual(voice.levels, [])
        XCTAssertEqual(voice.release(), [.send(waveform: Waveform.encode([]))], "800 ms from the touch is not a slip")
    }
}
