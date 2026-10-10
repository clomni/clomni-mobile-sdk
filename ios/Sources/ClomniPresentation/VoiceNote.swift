import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
#endif

/// A voice message's bubble, decided here so the view only draws it: the play button, the waveform filling as it
/// plays, the length (what is left while it plays), the speed. The same as the Android SDK's VoiceNote.
package struct VoiceNote: Sendable, Equatable, Identifiable {
    /// The player's key: the message's id, or the client id while it is on its way.
    package var id: String
    package var source: VoicePlayer.Source
    /// The message's own length; nil until the file says it.
    package var durationMs: Int?
    /// 0–100 each, or nil: plain bars.
    package var waveform: [Int]?
    package var outgoing: Bool
    /// The user's recording is still uploading: a ring turns inside the play button.
    package var sending: Bool

    package init(id: String, source: VoicePlayer.Source, durationMs: Int?, waveform: [Int]?, outgoing: Bool, sending: Bool = false) {
        self.id = id
        self.source = source
        self.durationMs = durationMs
        self.waveform = waveform
        self.outgoing = outgoing
        self.sending = sending
    }

    /// A message from the server: played from its file, fetched once.
    package init(id: String, audio: MessageContent.Audio, outgoing: Bool) {
        self.init(id: id, source: .remote(audio.url), durationMs: audio.durationMs, waveform: audio.waveform, outgoing: outgoing)
    }

    /// The user's own on its way (uploading, or waiting for the connection): played from the recording itself.
    package static func sending(clientId: String, file: URL, durationMs: Int?, waveform: [Int]?, uploading: Bool) -> VoiceNote {
        VoiceNote(id: clientId, source: .local(file), durationMs: durationMs, waveform: waveform, outgoing: true, sending: uploading)
    }

    /// The time under the waveform: what is left while it plays or waits half-heard, otherwise its length.
    package func time(_ track: VoicePlayer.Track) -> String {
        let started = track.phase == .playing || (track.phase == .paused && track.positionMs > 0)
        guard let duration = track.durationMs ?? durationMs else { return VoiceTime.clock(track.positionMs) }
        return started ? VoiceTime.remaining(duration - track.positionMs) : VoiceTime.length(duration)
    }

    /// VoiceOver's reading of the bubble: "Səsli mesaj, 0:14".
    package func accessibilityLabel(_ track: VoicePlayer.Track, strings: ClomniStrings) -> String {
        guard let duration = track.durationMs ?? durationMs else { return strings[.voiceMessage] }
        return "\(strings[.voiceMessage]), \(VoiceTime.length(duration))"
    }
}

/// Times of voice messages: "0:07", "1:05", "12:00".
package enum VoiceTime {
    /// A clock that runs (the recorder's timer, a position): whole seconds gone.
    package static func clock(_ ms: Int) -> String { format(max(0, ms) / 1000) }

    /// A length: the nearest second, at least one.
    package static func length(_ ms: Int) -> String { format(max(1, (ms + 500) / 1000)) }

    /// What is left: a part of a second still counts, so it reads 0:00 only at the end.
    package static func remaining(_ ms: Int) -> String { format(max(0, ms + 999) / 1000) }

    private static func format(_ seconds: Int) -> String {
        "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
    }
}
