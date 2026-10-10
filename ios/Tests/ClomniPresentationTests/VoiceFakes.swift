import Foundation
@testable import ClomniPresentation

/// A clock and its timers, moved by hand: `advance` runs whatever falls due, in order, at its own time.
final class FakeTime: VoiceScheduler {
    private(set) var now = 0
    private var timers: [(due: Int, order: Int, action: () -> Void)] = []
    private var order = 0

    func after(_ milliseconds: Int, _ action: @escaping () -> Void) -> () -> Void {
        let mine = order
        order += 1
        timers.append((now + milliseconds, mine, action))
        return { [weak self] in self?.timers.removeAll { $0.order == mine } }
    }

    func advance(_ ms: Int) {
        let end = now + ms
        while let next = timers.filter({ $0.due <= end }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            timers.removeAll { $0.order == next.order }
            now = next.due
            next.action()
        }
        now = end
    }

    var pending: Int { timers.count }
}

/// The microphone's test double (CI has none): writes a few bytes where it records, measures by `time`.
final class FakeMic: MicInput {
    var starts = true
    var stopsEmpty = false
    var loudness = 0.5
    private(set) var started: [URL] = []
    private(set) var stops = 0
    private(set) var cancels = 0
    private let time: FakeTime
    private var startedAt = 0

    init(time: FakeTime) { self.time = time }

    func start(_ file: URL) -> Bool {
        guard starts else { return false }
        FileManager.default.createFile(atPath: file.path, contents: Data("m4a".utf8))
        started.append(file)
        startedAt = time.now
        return true
    }

    func level() -> Double { loudness }

    func stop() -> Int? {
        stops += 1
        if stopsEmpty {
            try? FileManager.default.removeItem(at: started.last!)
            return nil
        }
        return time.now - startedAt
    }

    func cancel() {
        cancels += 1
        if let file = started.last { try? FileManager.default.removeItem(at: file) }
    }
}

/// The speaker's double: what was asked of it, in order; the test answers through `listener`.
final class FakeOutput: AudioOutput {
    var calls: [String] = []
    var listener: AudioOutputListener?
    var positionMs = 0
    var lengths: [URL: Int] = [:]

    func open(_ file: URL, listener: AudioOutputListener) {
        calls.append("open \(file.lastPathComponent)")
        self.listener = listener
    }

    func play(rate: Double) { calls.append("play \(rate)") }
    func pause() { calls.append("pause") }

    func seek(to positionMs: Int) {
        self.positionMs = positionMs
        calls.append("seek \(positionMs)")
    }

    func setRate(_ rate: Double) { calls.append("rate \(rate)") }
    func close() { calls.append("close") }
    func duration(of file: URL) -> Int? { lengths[file] }
}

/// Fetches that wait for the test to answer them.
final class FakeFiles: VoiceFiles {
    var asked: [(url: URL, done: (URL?) -> Void)] = []

    func fetch(_ url: URL, done: @escaping (URL?) -> Void) { asked.append((url, done)) }
    func answer(_ index: Int, _ file: URL?) { asked[index].done(file) }
}

/// A folder of its own for a test's files.
func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clomni-voice-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
