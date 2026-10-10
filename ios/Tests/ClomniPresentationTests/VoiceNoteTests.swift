import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniPresentation

/// What the voice bubble says and reads out (as Android's VoiceNoteTest).
final class VoiceNoteTests: XCTestCase {
    private let az = ClomniStrings(language: "az")
    private let audio = MessageContent.Audio(url: URL(string: "https://app.clomni.ai/f/voice-7d1c.m4a")!, mime: "audio/mp4",
                                             size: 96_412, durationMs: 14_260, waveform: [1, 2])
    private lazy var note = VoiceNote(id: "msg_f100", audio: audio, outgoing: true)

    func testTimes() {
        XCTAssertEqual(VoiceTime.clock(999), "0:00")
        XCTAssertEqual(VoiceTime.clock(7_900), "0:07")
        XCTAssertEqual(VoiceTime.clock(65_000), "1:05")
        XCTAssertEqual(VoiceTime.clock(720_000), "12:00")
        XCTAssertEqual(VoiceTime.clock(-5), "0:00")
        XCTAssertEqual(VoiceTime.length(14_260), "0:14")
        XCTAssertEqual(VoiceTime.length(14_500), "0:15")
        XCTAssertEqual(VoiceTime.length(200), "0:01", "a length is never nothing")
        XCTAssertEqual(VoiceTime.remaining(4_001), "0:05")
        XCTAssertEqual(VoiceTime.remaining(1), "0:01")
        XCTAssertEqual(VoiceTime.remaining(0), "0:00")
        XCTAssertEqual(VoiceTime.remaining(-30), "0:00")
    }

    func testTheBubbleShowsTheLengthThenWhatIsLeft() {
        XCTAssertEqual(note.source, .remote(audio.url))
        XCTAssertEqual(note.time(.init()), "0:14")
        XCTAssertEqual(note.time(.init(phase: .loading)), "0:14")
        XCTAssertEqual(note.time(.init(phase: .playing, positionMs: 3_300, durationMs: 14_260)), "0:11")
        XCTAssertEqual(note.time(.init(phase: .paused, positionMs: 3_300, durationMs: 14_260)), "0:11", "paused half-heard")
        XCTAssertEqual(note.time(.init(phase: .paused, positionMs: 0, durationMs: 14_260)), "0:14")
        XCTAssertEqual(note.time(.init(phase: .idle, positionMs: 0, durationMs: 20_000)), "0:20", "the file's own length wins")
        var unknown = note
        unknown.durationMs = nil
        XCTAssertEqual(unknown.time(.init()), "0:00")
        XCTAssertEqual(unknown.time(.init(phase: .playing, positionMs: 3_300)), "0:03")
    }

    func testVoiceOverReadsWhatItIsAndHowLong() {
        XCTAssertEqual(note.accessibilityLabel(.init(), strings: az), "Səsli mesaj, 0:14")
        var unknown = note
        unknown.durationMs = nil
        XCTAssertEqual(unknown.accessibilityLabel(.init(), strings: az), "Səsli mesaj")
        XCTAssertEqual(unknown.accessibilityLabel(.init(durationMs: 61_000), strings: az), "Səsli mesaj, 1:01")
        XCTAssertEqual(note.accessibilityLabel(.init(), strings: ClomniStrings(language: "en")), "Voice message, 0:14")
        XCTAssertEqual(note.accessibilityLabel(.init(), strings: ClomniStrings(language: "ru")), "Голосовое сообщение, 0:14")
    }

    func testTheUsersOwnOnItsWayPlaysFromTheDisk() {
        let file = URL(fileURLWithPath: "/tmp/voice-1.m4a")
        let sending = VoiceNote.sending(clientId: "client-1", file: file, durationMs: 3_000, waveform: [1, 2], uploading: true)
        XCTAssertEqual(sending.source, .local(file))
        XCTAssertTrue(sending.outgoing && sending.sending)
        XCTAssertEqual(sending.time(.init()), "0:03")
        XCTAssertFalse(VoiceNote(id: "msg_1", audio: audio, outgoing: false).sending)
    }

    func testTheRecordersTexts() {
        XCTAssertEqual(az[.voiceSlideToCancel], "Ləğv etmək üçün sürüşdürün")
        XCTAssertEqual(az[.voiceHoldToRecord], "Yazmaq üçün basıb saxlayın")
        XCTAssertEqual(az.format(.voiceMaxLength, 5), "Ən çox 5 dəqiqə")
        XCTAssertEqual(ClomniStrings(language: "en").format(.voiceMaxLength, 1), "Up to 1 min")
        XCTAssertEqual(ClomniStrings(language: "az", overrides: ["voice_record": "Səs yaz"])[.voiceRecord], "Səs yaz")
    }
}
