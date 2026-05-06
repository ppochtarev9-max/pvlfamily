import Foundation

enum AnalyticsFormatters {
    private enum TrackerDateFormatters {
        static let isoDay: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        static let dayLabelRU: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd.MM"
            f.locale = Locale(identifier: "ru_RU")
            return f
        }()
    }

    static func sleepDuration(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        if h > 0, m > 0 { return "\(h)ч \(m)м" }
        if h > 0 { return "\(h)ч" }
        return "\(m)м"
    }

    static func sleepDurationWithMinutesHint(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        return "\(sleepDuration(minutes)) (\(minutes)м)"
    }

    static func dayLabelDDMM(fromISO iso: String) -> String {
        guard let d = TrackerDateFormatters.isoDay.date(from: iso) else { return iso }
        return TrackerDateFormatters.dayLabelRU.string(from: d)
    }

    static func moneyRU(_ v: Double) -> String {
        let n = Int(v.rounded())
        let s = String(format: "%d", abs(n))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out = " " + out }
            out = String(c) + out
        }
        return (n < 0 ? "−" : "") + out + " ₽"
    }
}
