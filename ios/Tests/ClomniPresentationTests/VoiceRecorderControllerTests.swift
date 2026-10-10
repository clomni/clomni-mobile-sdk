import Foundation
import XCTest
@testable import ClomniPresentation

/// The recorder against a microphone double: what is recorded, sent, kept or thrown away (as Android's tests).
final class VoiceRecorderControllerTests: XCTestCase {
    private let folder = temporaryFolder()
    private let time = FakeTime()
    private lazy var mic = FakeMic(time: time)
    private var permission = VoiceRecording.Permission.granted
    private var asked = 0
    private var sent: [VoiceClip] = []
    private var feedback: [VoiceRecorderController.Feedback] = []
    private var changes = 0
    private var files = 0

    private func recorder(maxMs: Int = 300_000) -> VoiceRecorderController {
        let recorder = VoiceRecorderController(
            mic: mic, permission: { [unowned self] in permission }, askPermission: { [unowned self] in asked += 1 },
            newFile: { [unowned self] in files += 1; return folder.appendingPathComponent("voice-\(files).m4a") },
            scheduler: time, now: { [unowned self] in time.now }, maxMs: maxMs,
            send: { [unowned self] in sent.append($0) }, feedback: { [unowned self] in feedback.append($0) })
        recorder.onChange = { [unowned self] in changes += 1 }
        return recorder
    }

    private func exists(_ file: URL) -> Bool { FileManager.default.fileExists(atPath: file.path) }

    func testHoldAndLetGoSendsTheRecordingWithItsLengthAndWaveform() throws {
        let recorder = recorder()
        recorder.press()
        XCTAssertEqual(mic.started.count, 1)
        XCTAssertEqual(feedback, [.start])
        mic.loudness = 0.8
        time.advance(1_500)
        XCTAssertEqual(recorder.state, .holding(elapsedMs: 1_500, cancel: 0, lock: 0))
        XCTAssertEqual(recorder.levels.count, 30, "a level each 50 ms tick")
        XCTAssertGreaterThanOrEqual(changes, 30)
        recorder.release()
        let clip = try XCTUnwrap(sent.first)
        XCTAssertEqual(clip, VoiceClip(file: mic.started[0], durationMs: 1_500, waveform: Array(repeating: 80, count: 64)))
        XCTAssertTrue(exists(clip.file))
        XCTAssertEqual(time.pending, 0, "the clock stops with it")
    }

    func testAShortPressAsksToHoldForTwoSeconds() {
        let recorder = recorder()
        recorder.press()
        time.advance(300)
        recorder.release()
        XCTAssertEqual(sent, [])
        XCTAssertEqual(mic.cancels, 1)
        XCTAssertFalse(exists(mic.started[0]))
        XCTAssertEqual(recorder.hint, .hold)
        XCTAssertEqual(recorder.discards, 0, "no bin for a slip")
        time.advance(1_999)
        XCTAssertEqual(recorder.hint, .hold)
        time.advance(1)
        XCTAssertNil(recorder.hint)
    }

    func testSlidingAwayThrowsItIntoTheBin() {
        let recorder = recorder()
        recorder.press()
        time.advance(2_000)
        recorder.drag(dx: -130, dy: 0)
        XCTAssertEqual(mic.cancels, 1)
        XCTAssertEqual(recorder.discards, 1)
        XCTAssertEqual(feedback, [.start, .cancel])
        recorder.release()
        XCTAssertEqual(sent, [])
    }

    func testLockedStoppedHeardThenSent() throws {
        let recorder = recorder()
        recorder.press()
        time.advance(1_000)
        recorder.drag(dx: 0, dy: -100)
        XCTAssertEqual(feedback.last, .lock)
        recorder.release()
        time.advance(4_000)
        XCTAssertEqual(recorder.state, .locked(elapsedMs: 5_000))
        recorder.stop()
        let review = try XCTUnwrap(recorder.review)
        XCTAssertEqual(review.durationMs, 5_000)
        time.advance(10_000)
        XCTAssertEqual(recorder.levels.count, 100, "nothing records while it is heard")
        recorder.sendNow()
        XCTAssertEqual(sent, [review])
        XCTAssertNil(recorder.review)
        XCTAssertEqual(mic.stops, 1)
    }

    func testDeletedWhileHeard() throws {
        let recorder = recorder()
        recorder.pressLocked()
        time.advance(2_000)
        recorder.stop()
        let file = try XCTUnwrap(recorder.review?.file)
        recorder.delete()
        XCTAssertFalse(exists(file))
        XCTAssertEqual(recorder.discards, 1)
        XCTAssertEqual(sent, [])
    }

    func testTheLimitStopsItAndSaysSo() {
        let recorder = recorder(maxMs: 3_000)
        recorder.press()
        time.advance(3_000)
        XCTAssertEqual(recorder.state, .review(durationMs: 3_000))
        XCTAssertEqual(recorder.hint, .limit)
        recorder.release()
        XCTAssertEqual(sent, [], "letting go does not send it")
        recorder.sendNow()
        XCTAssertEqual(sent.first?.durationMs, 3_000)
    }

    func testPermission() {
        permission = .undecided
        let recorder = recorder()
        recorder.press()
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(mic.started, [])
        permission = .denied
        recorder.press()
        XCTAssertEqual(recorder.hint, .denied)
        time.advance(VoiceRecorderController.deniedHintMs)
        XCTAssertNil(recorder.hint)
        permission = .granted
        recorder.press()
        XCTAssertEqual(mic.started.count, 1)
    }

    func testAMicrophoneThatWillNotStartOrRecordedNothing() {
        let recorder = recorder()
        mic.starts = false
        recorder.press()
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(time.pending, 0)
        mic.starts = true
        mic.stopsEmpty = true
        recorder.press()
        time.advance(1_000)
        recorder.release()
        XCTAssertEqual(sent, [])
        recorder.pressLocked()
        time.advance(1_000)
        recorder.stop()
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNil(recorder.review)
    }

    func testClosingThrowsAwayWhatIsBeingRecordedOrHeard() throws {
        let recorder = recorder()
        recorder.press()
        time.advance(1_000)
        recorder.close()
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(mic.cancels, 1)
        XCTAssertEqual(time.pending, 0)
        recorder.pressLocked()
        time.advance(1_000)
        recorder.stop()
        let file = try XCTUnwrap(recorder.review?.file)
        recorder.close()
        XCTAssertFalse(exists(file))
        XCTAssertEqual(sent, [])
    }
}
