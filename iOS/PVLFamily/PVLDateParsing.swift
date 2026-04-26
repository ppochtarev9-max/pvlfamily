import Foundation

/// Парсинг дат с API: без `Z`, с пробелом вместо `T`, с долями секунд — `ISO8601DateFormatter` часто даёт `nil`, из‑за этого в UI оказываются «— — —».
enum PVLDateParsing {
    static func parse(_ string: String) -> Date? {
        let s0 = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s0.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s0) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s0) { return d }
        if s0.contains("T") {
            let hasTz = s0.contains("Z")
                || s0.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
            if !hasTz {
                let withZ = s0 + "Z"
                let z1 = ISO8601DateFormatter()
                z1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = z1.date(from: withZ) { return d }
                z1.formatOptions = [.withInternetDateTime]
                if let d = z1.date(from: withZ) { return d }
            }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        for fmt in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss"
        ] {
            f.dateFormat = fmt
            if let d = f.date(from: s0) { return d }
        }
        f.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s0) { return d }
        }
        return nil
    }

    static func timeHHmm(from string: String) -> String {
        if let d = parse(string) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "ru_RU")
            out.dateFormat = "HH:mm"
            return out.string(from: d)
        }
        if let t = timeSubstringLenient(string) { return t }
        return "—"
    }

    private static func timeSubstringLenient(_ s: String) -> String? {
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tIdx = str.firstIndex(of: "T") {
            return extractTime(from: String(str[str.index(after: tIdx)...]))
        }
        if let r = str.range(of: " ") {
            return extractTime(from: String(str[r.upperBound...]))
        }
        return nil
    }

    private static func extractTime(from timePortion: String) -> String? {
        let head = timePortion.split(separator: ".").map(String.init).first ?? timePortion
        let parts = head.split(separator: ":")
        guard let h0 = parts.first, let h = Int(h0) else { return nil }
        let m = parts.count > 1 ? (Int(String(parts[1].prefix(2))) ?? 0) : 0
        return String(format: "%02d:%02d", min(23, max(0, h)), min(59, max(0, m)))
    }

    static func eventWord(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1, n100 != 11 { return "событие" }
        if (2...4).contains(n10), n100 < 10 || n100 > 20 { return "события" }
        return "событий"
    }
}
