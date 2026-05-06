import Foundation

/// Парсинг дат с API: без `Z`, с пробелом вместо `T`, с долями секунд — `ISO8601DateFormatter` часто даёт `nil`, из‑за этого в UI оказываются «— — —».
enum PVLDateParsing {
    // DateFormatter/ISO8601DateFormatter создаются дорого; держим статически.
    // Примечание: DateFormatter не thread-safe, но в нашем UI-потоке это ок.
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoWithZAndFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoWithZNoFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let posixDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()
    private static let posixDateFormatterGMT: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
    private static let hhmmFormatterRU: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Кэш успешных парсингов (ускоряет повторные рендеры списков).
    private static var parseCache: [String: Date] = [:]
    private static var parseCacheOrder: [String] = []
    private static let parseCacheLimit = 500

    private static func cachePut(_ key: String, _ value: Date) {
        if parseCache[key] == nil {
            parseCacheOrder.append(key)
            if parseCacheOrder.count > parseCacheLimit, let oldest = parseCacheOrder.first {
                parseCacheOrder.removeFirst()
                parseCache.removeValue(forKey: oldest)
            }
        }
        parseCache[key] = value
    }

    static func parse(_ string: String) -> Date? {
        let s0 = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s0.isEmpty else { return nil }
        if let cached = parseCache[s0] { return cached }

        // Важно: timestamps из нашего API часто приходят *без* timezone (без `Z`/offset),
        // но подразумевают локальное время. Принудительное добавление `Z` превращает их в UTC
        // и сдвигает сутки → ломает группировку по дням и `isDateInToday`.
        if s0.contains("T") {
            let hasTz = s0.contains("Z")
                || s0.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
            if !hasTz {
                // Пробуем строго локальный парсинг до ISO8601 (который требует TZ).
                for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
                    posixDateFormatter.dateFormat = fmt
                    if let d = posixDateFormatter.date(from: s0) {
                        cachePut(s0, d)
                        return d
                    }
                }
            }
        }

        if let d = isoWithFractionalSeconds.date(from: s0) {
            cachePut(s0, d)
            return d
        }
        if let d = isoNoFractionalSeconds.date(from: s0) {
            cachePut(s0, d)
            return d
        }
        for fmt in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss"
        ] {
            posixDateFormatter.dateFormat = fmt
            if let d = posixDateFormatter.date(from: s0) {
                cachePut(s0, d)
                return d
            }
        }
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            posixDateFormatterGMT.dateFormat = fmt
            if let d = posixDateFormatterGMT.date(from: s0) {
                cachePut(s0, d)
                return d
            }
        }
        return nil
    }

    static func timeHHmm(from string: String) -> String {
        if let d = parse(string) {
            return hhmmFormatterRU.string(from: d)
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
