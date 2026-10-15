import Foundation
import RoamCore

enum Format {
    /// Temperature in the unit the person's region uses.
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func wind(_ kph: Double) -> String {
        Measurement(value: kph, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static var isMetric: Bool { Locale.current.measurementSystem == .metric }

    static func distance(_ meters: Double) -> String { Geo.format(meters: meters, metric: isMetric) }

    /// "Thu" for "2026-10-15", or "Today" for the first day.
    static func weekday(_ isoDate: String, isFirst: Bool) -> String {
        if isFirst { return "Today" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: isoDate) else { return isoDate }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let names = calendar.shortWeekdaySymbols
        return names[calendar.component(.weekday, from: date) - 1]
    }

    /// "3 hours ago".
    static func age(_ seconds: TimeInterval) -> String {
        let style = RelativeDateTimeFormatter()
        style.unitsStyle = .full
        return style.localizedString(for: Date(timeIntervalSinceNow: -seconds), relativeTo: .now)
    }

    static func population(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
