import Foundation

/// Times as the messenger writes them, in the device's time zone.
public struct TimeText: Sendable {
    private let strings: ClomniStrings
    private let calendar: Calendar

    public init(strings: ClomniStrings, timeZone: TimeZone = .current) {
        self.strings = strings
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// How long ago, for lists and the Home card: "indi", "2 dəq", "3 saat", "4 gün", then the date ("1 oktyabr").
    public func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return strings[.now]
        case ..<3_600: return strings.format(.minutesShort, seconds / 60)
        case ..<86_400: return strings.format(.hoursShort, seconds / 3_600)
        case ..<604_800: return strings.format(.daysShort, seconds / 86_400)
        default: return dayAndMonth(date, withYear: !sameYear(date, now))
        }
    }

    /// For the conversation's time separators: "Bu gün 10:30", "Dünən 10:30", "1 oktyabr 10:30", and with the year
    /// when it is not this one.
    public func day(_ date: Date, now: Date) -> String {
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return "\(strings[.today]) \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(strings[.yesterday]) \(time)"
        }
        let separator = strings.language == "en" ? ", " : " "
        return dayAndMonth(date, withYear: !sameYear(date, now)) + separator + time
    }

    /// 24-hour "10:30".
    public func clock(_ date: Date) -> String {
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
