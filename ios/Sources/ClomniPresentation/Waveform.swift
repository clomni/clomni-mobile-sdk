import Foundation

/// A voice message's waveform: the loudness the recorder measured, as the protocol carries it (audio.waveform: whole
/// numbers of 0–100, `points` of them from the SDKs) and as the bubble draws it (bar heights of 0–1). The same numbers
/// as the Android SDK's Waveform.
package enum Waveform {
    /// What an SDK sends with a voice message.
    package static let points = 64
    /// The quietest bar: silence still shows as a dot, as in WhatsApp.
    package static let floor = 0.12
    /// The bars of a recording without a waveform (an operator's MP3): plain, all one low height.
    package static let plain = 0.3
    /// Loudness under this many dB below full scale is silence.
    private static let rangeDB = 50.0

    /// A level of 0–1 from loudness in dBFS (AVAudioRecorder's averagePower): -50 dB and below is 0, 0 dB is 1.
    package static func level(decibels: Double) -> Double {
        min(1, max(0, (decibels + rangeDB) / rangeDB))
    }

    /// `levels` (0–1, one per tick of the recorder, in order) as `points` whole numbers of 0–100: each the loudest of
    /// its share of the ticks, so a short word still shows; fewer ticks than points are stretched. Empty for none.
    package static func encode(_ levels: [Double], points: Int = Waveform.points) -> [Int] {
        guard !levels.isEmpty else { return [] }
        return (0..<points).map { index in
            let share = Self.share(index, of: points, size: levels.count)
            let loudest = levels[share].max() ?? 0
            return Int((min(1, max(0, loudest)) * 100).rounded())
        }
    }

    /// `count` bar heights of 0–1 for `waveform` (0–100 each), at least `floor`; without one, `count` plain bars.
    package static func bars(_ waveform: [Int]?, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard let waveform, !waveform.isEmpty else { return Array(repeating: plain, count: count) }
        return (0..<count).map { index in
            let loudest = waveform[share(index, of: count, size: waveform.count)].max() ?? 0
            return floor + (1 - floor) * Double(min(100, max(0, loudest))) / 100
        }
    }

    /// The live waveform while recording: the newest `count` levels as bar heights, the newest at the end; `floor`
    /// before anything was heard.
    package static func live(_ levels: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let recent = levels.suffix(count).map { floor + (1 - floor) * min(1, max(0, $0)) }
        return Array(repeating: floor, count: count - recent.count) + recent
    }

    /// The share of `size` items that bar `index` of `count` stands for: at least one.
    private static func share(_ index: Int, of count: Int, size: Int) -> Range<Int> {
        let from = min(index * size / count, size - 1)
        let to = max(from + 1, (index + 1) * size / count)
        return from..<to
    }
}
