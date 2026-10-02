import Foundation
import XCTest
@testable import ClomniPresentation

final class StringsTests: XCTestCase {
    func testEveryKeyHasAzEnAndRu() {
        for language in ["az", "en", "ru"] {
            let strings = ClomniStrings(language: language)
            for key in ClomniStrings.Key.allCases {
                XCTAssertNotNil(ClomniStrings.fallbacks[language]?[key], "\(language) has no \(key)")
                XCTAssertFalse(strings[key].contains("—"), "plain punctuation only: \(strings[key])")
            }
            XCTAssertEqual(strings.months.count, 12)
        }
    }

    func testLanguageAndOverrides() {
        XCTAssertEqual(ClomniStrings(language: "en")[.tabMessages], "Messages")
        XCTAssertEqual(ClomniStrings(language: "ru-RU")[.tabHome], "Главная")
        XCTAssertEqual(ClomniStrings(language: "de")[.tabHome], "Ana səhifə", "anything else reads as az")
        XCTAssertEqual(ClomniStrings(language: nil).language, "az")
        // The panel's texts come first; an empty one does not hide the SDK's.
        let strings = ClomniStrings(language: "az", overrides: ["yesterday": "Dün", "send": "", "custom": "x"])
        XCTAssertEqual(strings[.yesterday], "Dün")
        XCTAssertEqual(strings[.send], "Göndər")
        XCTAssertEqual(strings.format(.minutesShort, 2), "2 dəq")
        XCTAssertEqual(strings.format(.awayUntil, "09:00"), "Növbəti iş saatı: 09:00")
        XCTAssertEqual(ClomniStrings(language: "en").format(.awayUntil, "09:00"), "Next working hours: 09:00")
        XCTAssertEqual(ClomniStrings(language: "ru").format(.awayUntil, "09:00"), "Следующее рабочее время: 09:00")
        XCTAssertEqual(ClomniStrings(language: "az")[.offline], "İnternet yoxdur")
    }

    /// The SDK's built-in texts are protocol/strings.json's, the server's defaults: a key the server has and the SDK
    /// uses must read the same before the config arrives as after.
    func testTheBuiltInTextsAreTheServers() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/strings.json")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var compared = 0
        for language in ["az", "en", "ru"] {
            let server = try XCTUnwrap(json[language] as? [String: String], language)
            let strings = ClomniStrings(language: language)
            for (raw, text) in server {
                guard let key = ClomniStrings.Key(rawValue: raw) else { continue }
                XCTAssertEqual(strings[key], text, "\(language) \(raw)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 100)
    }
}

final class TimeTextTests: XCTestCase {
    private let baku = TimeZone(identifier: "Asia/Baku")!
    /// 2026-10-01 10:30 in Baku.
    private let now = Date(timeIntervalSince1970: 1_790_836_200)

    private func text(_ language: String) -> TimeText {
        TimeText(strings: ClomniStrings(language: language), timeZone: baku)
    }

    func testAgo() {
        let az = text("az")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-30), now: now), "indi")
        XCTAssertEqual(az.ago(now.addingTimeInterval(120), now: now), "indi", "a clock running ahead is now")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-130), now: now), "2 dəq")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-3 * 3_600 - 5), now: now), "3 saat")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-2 * 86_400), now: now), "2 gün")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-10 * 86_400), now: now), "21 sentyabr")
        XCTAssertEqual(az.ago(now.addingTimeInterval(-300 * 86_400), now: now), "5 dekabr 2025")
        XCTAssertEqual(text("en").ago(now.addingTimeInterval(-130), now: now), "2 min")
        XCTAssertEqual(text("en").ago(now.addingTimeInterval(-300 * 86_400), now: now), "December 5, 2025")
        XCTAssertEqual(text("ru").ago(now.addingTimeInterval(-10 * 86_400), now: now), "21 сентября")
        XCTAssertEqual(text("ru").ago(now.addingTimeInterval(-60), now: now), "1 мин")
    }

    func testDay() {
        let az = text("az")
        XCTAssertEqual(az.day(now, now: now), "Bu gün 10:30")
        XCTAssertEqual(az.day(now.addingTimeInterval(-10 * 3_600 - 25 * 60), now: now), "Bu gün 00:05")
        XCTAssertEqual(az.day(now.addingTimeInterval(-11 * 3_600), now: now), "Dünən 23:30")
        XCTAssertEqual(az.day(now.addingTimeInterval(-3 * 86_400), now: now), "28 sentyabr 10:30")
        XCTAssertEqual(az.day(now.addingTimeInterval(-300 * 86_400), now: now), "5 dekabr 2025 10:30")
        XCTAssertEqual(text("en").day(now, now: now), "Today 10:30")
        XCTAssertEqual(text("en").day(now.addingTimeInterval(-3 * 86_400), now: now), "September 28, 10:30")
        XCTAssertEqual(text("ru").day(now.addingTimeInterval(-11 * 3_600), now: now), "Вчера 23:30")
        // The panel's "Dün" replaces the SDK's "Dünən".
        let custom = TimeText(strings: ClomniStrings(language: "az", overrides: ["yesterday": "Dün"]), timeZone: baku)
        XCTAssertEqual(custom.day(now.addingTimeInterval(-11 * 3_600), now: now), "Dün 23:30")
        XCTAssertEqual(TimeText(strings: ClomniStrings(language: "az"), timeZone: TimeZone(identifier: "UTC")!)
            .clock(now), "06:30", "the device's time zone")
    }

    /// The header's "away_until": the day only when it is not today.
    func testUpcoming() {
        let az = text("az")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(90 * 60), now: now), "12:00")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(13 * 3_600 + 29 * 60), now: now), "23:59")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(13 * 3_600 + 30 * 60), now: now), "sabah 00:00")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(22 * 3_600 + 30 * 60), now: now), "sabah 09:00")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(46 * 3_600 + 30 * 60), now: now), "3 oktyabr 09:00")
        XCTAssertEqual(az.upcoming(now.addingTimeInterval(100 * 86_400), now: now), "9 yanvar 2027 10:30")
        XCTAssertEqual(text("en").upcoming(now.addingTimeInterval(22 * 3_600 + 30 * 60), now: now), "tomorrow 09:00")
        XCTAssertEqual(text("en").upcoming(now.addingTimeInterval(46 * 3_600 + 30 * 60), now: now), "October 3, 09:00")
        XCTAssertEqual(text("ru").upcoming(now.addingTimeInterval(22 * 3_600 + 30 * 60), now: now), "завтра 09:00")
        XCTAssertEqual(text("ru").upcoming(now.addingTimeInterval(90 * 60), now: now), "12:00")
    }
}
