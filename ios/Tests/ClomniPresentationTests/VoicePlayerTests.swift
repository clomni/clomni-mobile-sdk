import Foundation
import XCTest
@testable import ClomniPresentation

/// Playing voice messages one at a time, against a fake speaker and fake fetches (as Android's VoicePlayerTest).
final class VoicePlayerTests: XCTestCase {
    private let folder = temporaryFolder()
    private let time = FakeTime()
    private let output = FakeOutput()
    private let files = FakeFiles()
    private lazy var player = VoicePlayer(files: files, output: output, scheduler: time)
    private let first = VoicePlayer.Source.remote(URL(string: "https://app.clomni.ai/f/1.m4a")!)
    private let second = VoicePlayer.Source.remote(URL(string: "https://app.clomni.ai/f/2.mp3")!)

    private func file(_ name: String) -> URL {
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("audio".utf8))
        return url
    }

    /// Message `id` fetched, opened and ready: playing.
    private func playing(_ id: String = "a", _ source: VoicePlayer.Source? = nil, length: Int = 10_000) {
        player.toggle(id, source: source ?? first, knownDurationMs: nil)
        files.answer(files.asked.count - 1, file("\(id).m4a"))
        output.listener?.ready(durationMs: length)
    }

    func testFetchesOpensAndPlaysThenTicks() {
        player.toggle("a", source: first, knownDurationMs: 14_260)
        XCTAssertEqual(player.track("a"), .init(phase: .loading, positionMs: 0, durationMs: 14_260))
        XCTAssertEqual(files.asked.map(\.url.absoluteString), ["https://app.clomni.ai/f/1.m4a"])
        files.answer(0, file("a.m4a"))
        XCTAssertEqual(output.calls, ["open a.m4a"])
        output.listener?.ready(durationMs: 14_300)
        XCTAssertEqual(output.calls, ["open a.m4a", "play 1.0"])
        XCTAssertEqual(player.track("a"), .init(phase: .playing, positionMs: 0, durationMs: 14_300))
        output.positionMs = 1_000
        time.advance(VoicePlayer.tickMs)
        XCTAssertEqual(player.track("a").positionMs, 1_000)
        XCTAssertEqual(player.track("a").progress, 1_000.0 / 14_300, accuracy: 0.0001)
    }

    func testASecondTapPausesAndAThirdGoesOn() {
        playing()
        output.positionMs = 3_000
        player.toggle("a", source: first, knownDurationMs: nil)
        XCTAssertEqual(player.track("a"), .init(phase: .paused, positionMs: 3_000, durationMs: 10_000))
        XCTAssertEqual(output.calls.last, "pause")
        XCTAssertEqual(time.pending, 0, "no ticks while paused")
        player.toggle("a", source: first, knownDurationMs: nil)
        XCTAssertEqual(player.track("a").phase, .playing)
        XCTAssertEqual(output.calls.last, "play 1.0")
        XCTAssertEqual(files.asked.count, 1, "fetched once")
    }

    func testStartingAnotherPausesTheFirstWhereItWas() {
        playing("a")
        output.positionMs = 4_000
        player.toggle("b", source: second, knownDurationMs: 7_000)
        XCTAssertEqual(player.track("a"), .init(phase: .paused, positionMs: 4_000, durationMs: 10_000))
        XCTAssertEqual(player.track("b").phase, .loading)
        files.answer(1, file("b.mp3"))
        output.positionMs = 0
        output.listener?.ready(durationMs: 7_000)
        XCTAssertEqual(player.track("b").phase, .playing)
        player.toggle("a", source: first, knownDurationMs: nil)
        XCTAssertEqual(player.track("b").phase, .paused)
        files.answer(2, file("a.m4a"))
        output.listener?.ready(durationMs: 10_000)
        XCTAssertEqual(Array(output.calls.suffix(2)), ["seek 4000", "play 1.0"])
        XCTAssertEqual(player.track("a"), .init(phase: .playing, positionMs: 4_000, durationMs: 10_000))
    }

    func testSpeedIsOneForAllAndChangesWhatPlays() {
        XCTAssertEqual(player.speed, .normal)
        player.cycleSpeed()
        XCTAssertEqual(player.speed, .fast)
        XCTAssertEqual(output.calls, [], "nothing plays: nothing to tell")
        playing()
        XCTAssertEqual(output.calls.last, "play 1.5")
        player.cycleSpeed()
        XCTAssertEqual(output.calls.last, "rate 2.0")
        XCTAssertEqual(player.speed.label, "2×")
        player.cycleSpeed()
        XCTAssertEqual(player.speed, .normal)
        XCTAssertEqual(output.calls.last, "rate 1.0")
    }

    func testSeekingWhilePlayingAndBeforePlaying() {
        playing()
        player.seek("a", to: 0.25, knownDurationMs: nil)
        XCTAssertEqual(output.calls.last, "seek 2500")
        player.seek("b", to: 0.5, knownDurationMs: 8_000)
        XCTAssertEqual(player.track("b"), .init(phase: .paused, positionMs: 4_000, durationMs: 8_000))
        XCTAssertEqual(output.calls.last, "seek 2500", "only the open file moves")
        player.seek("c", to: 0.5, knownDurationMs: nil)
        XCTAssertEqual(player.track("c"), .init())
        player.seek("b", to: 3, knownDurationMs: 8_000)
        XCTAssertEqual(player.track("b").positionMs, 8_000)
    }

    func testTheEndGoesBackToTheStart() {
        playing()
        output.positionMs = 10_000
        output.listener?.finished()
        XCTAssertEqual(player.track("a"), .init(phase: .idle, positionMs: 0, durationMs: 10_000))
        XCTAssertEqual(time.pending, 0)
        player.toggle("a", source: first, knownDurationMs: nil)
        XCTAssertEqual(player.track("a").phase, .loading, "opened again")
    }

    func testFailuresAndTapsWhileLoading() {
        player.toggle("a", source: first, knownDurationMs: nil)
        files.answer(0, nil)
        XCTAssertEqual(player.track("a").phase, .failed)
        player.toggle("a", source: first, knownDurationMs: nil)
        files.answer(1, file("a.m4a"))
        output.listener?.failed()
        XCTAssertEqual(player.track("a").phase, .failed)
        player.toggle("b", source: second, knownDurationMs: nil)
        player.toggle("b", source: second, knownDurationMs: nil)
        XCTAssertEqual(player.track("b").phase, .idle)
        files.answer(2, file("b.mp3"))
        XCTAssertEqual(output.calls.filter { $0.hasPrefix("open") }, ["open a.m4a"], "b never opened")
    }

    func testAnswersForAnEarlierFileAreDropped() {
        player.toggle("a", source: first, knownDurationMs: nil)
        player.toggle("b", source: second, knownDurationMs: nil)
        XCTAssertEqual(player.track("a").phase, .idle)
        files.answer(0, file("a.m4a"))
        XCTAssertEqual(output.calls, [], "a's fetch came too late")
        files.answer(1, file("b.mp3"))
        let stale = output.listener
        player.toggle("a", source: first, knownDurationMs: nil)
        stale?.ready(durationMs: 5_000)
        XCTAssertEqual(player.track("a").phase, .loading)
        XCTAssertEqual(player.track("b").phase, .idle)
    }

    func testTheUsersOwnRecordingPlaysFromTheDisk() {
        player.toggle("client-1", source: .local(file("voice-1.m4a")), knownDurationMs: 3_000)
        XCTAssertEqual(files.asked.count, 0)
        XCTAssertEqual(output.calls, ["open voice-1.m4a"])
        output.listener?.ready(durationMs: 3_000)
        XCTAssertEqual(player.track("client-1").phase, .playing)
    }

    func testAnInterruptionPausesAndReleaseLetsGo() {
        playing()
        output.positionMs = 2_000
        output.listener?.interrupted()
        XCTAssertEqual(player.track("a"), .init(phase: .paused, positionMs: 2_000, durationMs: 10_000))
        player.toggle("a", source: first, knownDurationMs: nil)
        player.release()
        XCTAssertEqual(player.track("a").phase, .paused)
        XCTAssertEqual(output.calls.last, "close")
        XCTAssertEqual(time.pending, 0)
    }

    func testPrefetchLearnsTheLengthOnce() {
        let mp3 = file("b.mp3")
        output.lengths[mp3] = 61_000
        player.prefetch("b", url: URL(string: "https://app.clomni.ai/f/2.mp3")!)
        player.prefetch("b", url: URL(string: "https://app.clomni.ai/f/2.mp3")!)
        XCTAssertEqual(files.asked.count, 1)
        files.answer(0, mp3)
        XCTAssertEqual(player.track("b"), .init(phase: .idle, positionMs: 0, durationMs: 61_000))
        player.seek("c", to: 0, knownDurationMs: 5_000)
        player.prefetch("c", url: URL(string: "https://app.clomni.ai/f/1.m4a")!)
        XCTAssertEqual(files.asked.count, 1)
    }

    func testEveryChangeIsHeard() {
        var changes = 0
        player.onChange = { changes += 1 }
        playing()
        let before = changes
        time.advance(VoicePlayer.tickMs * 3)
        XCTAssertEqual(changes, before + 3)
    }
}
