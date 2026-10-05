import Foundation

/// Times as the messenger writes them, in the device's time zone.
package struct TimeText: Sendable {
    private let strings: ClomniStrings
    private let calendar: Calendar

    package init(strings: ClomniStrings, timeZone: TimeZone = .current) {
        self.strings = strings
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// How long ago, for lists and the Home card: "indi", "2 dəq", "3 saat", "4 gün", then the date ("1 oktyabr").
    package func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return strings[.now]
        case ..<3_600: return strings.format(.minutesShort, seconds / 60)
        case ..<86_400: return strings.format(.hoursShort, seconds / 3_600)
        case ..<604_800: return strings.format(.daysShort, seconds / 86_400)
        default: return dayAndMonth(date, withYear: !sameYear(date, now))
        }
    }

    /// Under the last bubble of a run: "indi" within a minute, then the clock ("12:42").
    package func stamp(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? strings[.now] : clock(date)
    }

    /// For the conversation's time separators: "Bu gün 10:30", "Dünən 10:30", "1 oktyabr 10:30", and with the year
    /// when it is not this one.
    package func day(_ date: Date, now: Date) -> String {
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return "\(strings[.today]) \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(strings[.yesterday]) \(time)"
        }
        let separator = strings.language == "en" ? ", " : " "
        return dayAndMonth(date, withYear: !sameYear(date, now)) + separator + time
    }

    /// When something comes next, as the header's "away_until" says it: "09:00" today, "sabah 09:00" tomorrow,
    /// "2 oktyabr 09:00" later, with the year when it is not this one.
    package func upcoming(_ date: Date, now: Date) -> String {
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(strings[.tomorrow]) \(time)"
        }
        let separator = strings.language == "en" ? ", " : " "
        return dayAndMonth(date, withYear: !sameYear(date, now)) + separator + time
    }

    /// 24-hour "10:30".
    package func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func dayAndMonth(_ date: Date, withYear: Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = strings.months[(parts.month ?? 1) - 1]
        let day = parts.day ?? 1
        let year = withYear ? parts.year.map { String($0) } : nil
        if strings.language == "en" {
            return "\(month) \(day)" + (year.map { ", \($0)" } ?? "")
        }
        return "\(day) \(month)" + (year.map { " \($0)" } ?? "")
    }

    private func sameYear(_ a: Date, _ b: Date) -> Bool {
        calendar.component(.year, from: a) == calendar.component(.year, from: b)
    }
}
