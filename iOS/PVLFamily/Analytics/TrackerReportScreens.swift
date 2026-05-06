import SwiftUI
import Foundation
import Charts

// MARK: - Сравнение двух последних недель

struct TrackerCompareWeeksReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats { weeksContent(s) }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Неделя к неделе")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func weeksContent(_ s: TrackerStats) -> some View {
        let parts = twoWeeksSplit(s.daily_breakdown)
        let diff = parts.1 - parts.0
        reportScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Сравнение: предыдущие 7 дней vs последние 7 дней (по дате).")
                    .font(.subheadline)
                    .foregroundStyle(FamilyAppStyle.captionMuted)
                HStack(alignment: .top) {
                    weekColumn(title: "Раньше (ранние 7 в окне 14д)", minutes: parts.0, days: 7)
                    weekColumn(title: "Позже (последние 7)", minutes: parts.1, days: 7)
                }
                if #available(iOS 17.0, *) {
                    Chart(weekBars(parts: parts), id: \.label) { item in
                        BarMark(
                            x: .value("Неделя", item.label),
                            y: .value("Минуты", item.minutes)
                        )
                        .foregroundStyle(FamilyAppStyle.accent.gradient)
                    }
                    .frame(height: 180)
                }
                Text(diff >= 0 ? "Во второй неделе суммарно на \(AnalyticsFormatters.sleepDuration(abs(diff))) дольше." : "Во второй неделе суммарно на \(AnalyticsFormatters.sleepDuration(abs(diff))) меньше.")
                    .font(.footnote)
                    .foregroundStyle(FamilyAppStyle.captionMuted)
            }
        }
    }

    private func twoWeeksSplit(_ days: [DailyStat]) -> (Int, Int) {
        let sorted = days.sorted { $0.date < $1.date }
        let first7 = Array(sorted.prefix(7))
        let last7 = Array(sorted.suffix(min(7, sorted.count)))
        return (
            first7.map(\.sleep_minutes).reduce(0, +),
            last7.map(\.sleep_minutes).reduce(0, +)
        )
    }

    private func weekColumn(title: String, minutes: Int, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(AnalyticsFormatters.sleepDuration(minutes))
                .font(.title2.weight(.bold))
            Text("Σ минут / ~7 дн.")
                .font(.caption2)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekBars(parts: (Int, Int)) -> [(label: String, minutes: Int)] {
        [("Раньше", parts.0), ("Позже", parts.1)]
    }

    private func reportScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 14) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Средние (7 / 30 дней)

struct TrackerAveragesReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var s7: TrackerStats?
    @State private var s30: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if #available(iOS 17.0, *) {
                            Chart(avgBars(), id: \.period) { item in
                                BarMark(
                                    x: .value("Период", item.period),
                                    y: .value("Минуты", item.perDay)
                                )
                                .foregroundStyle(item.period == "7д" ? FamilyAppStyle.accent : FamilyAppStyle.captionMuted)
                            }
                            .frame(height: 180)
                        }
                        if let a = s7, a.total_sessions > 0 {
                            row("7 дней", avg: a.total_sleep_minutes / a.total_sessions, perDay: a.total_sleep_minutes / 7)
                        }
                        if let b = s30, b.total_sessions > 0 {
                            row("30 дней", avg: b.total_sleep_minutes / b.total_sessions, perDay: b.total_sleep_minutes / 30)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Средние за период")
        .onAppear(perform: load)
    }

    private func row(_ title: String, avg: Int, perDay: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("Средний эпизод: \(AnalyticsFormatters.sleepDuration(avg))")
            Text("Средне за сутки (Σ/дни): \(AnalyticsFormatters.sleepDuration(perDay))")
                .font(.footnote)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func avgBars() -> [(period: String, perDay: Int)] {
        var rows: [(String, Int)] = []
        if let a = s7 { rows.append(("7д", a.total_sleep_minutes / max(1, 7))) }
        if let b = s30 { rows.append(("30д", b.total_sleep_minutes / max(1, 30))) }
        return rows
    }

    private func load() {
        isLoading = true
        let g = DispatchGroup()
        g.enter()
        authManager.getTrackerStats(days: 7) { r in defer { g.leave() }; if case .success(let s) = r { s7 = s } }
        g.enter()
        authManager.getTrackerStats(days: 30) { r in defer { g.leave() }; if case .success(let s) = r { s30 = s } }
        g.notify(queue: .main) {
            isLoading = false
        }
    }
}

// MARK: - Выбросы (дни с аномальным сном)

struct TrackerOutlierDaysReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let out = Self.outliers(from: s.daily_breakdown)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if #available(iOS 17.0, *) {
                            Chart(s.daily_breakdown, id: \.date) { d in
                                LineMark(
                                    x: .value("Дата", formatDay(d.date)),
                                    y: .value("Минуты", d.sleep_minutes)
                                )
                                .foregroundStyle(FamilyAppStyle.accent)
                            }
                            .frame(height: 220)
                        }
                        GroupBox("Сильно выше нормы") {
                            if out.high.isEmpty { Text("—").foregroundStyle(.secondary) }
                            ForEach(out.high, id: \.date) { d in
                                HStack {
                                    Text(formatDay(d.date))
                                    Spacer()
                                    Text(AnalyticsFormatters.sleepDuration(d.sleep_minutes))
                                }
                            }
                        }
                        GroupBox("Сильно ниже нормы") {
                            if out.low.isEmpty { Text("—").foregroundStyle(.secondary) }
                            ForEach(out.low, id: \.date) { d in
                                HStack {
                                    Text(formatDay(d.date))
                                    Spacer()
                                    Text(AnalyticsFormatters.sleepDuration(d.sleep_minutes))
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Дни-выбросы")
        .onAppear(perform: load)
    }

    private static func outliers(from days: [DailyStat]) -> (high: [DailyStat], low: [DailyStat]) {
        let vals = days.filter { $0.sleep_minutes > 0 }.map { $0.sleep_minutes }
        guard vals.count > 2 else { return ([], []) }
        let mean = Double(vals.reduce(0, +)) / Double(vals.count)
        let varc = vals.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(vals.count)
        let sd = sqrt(varc)
        guard sd > 1 else { return ([], []) }
        let hi = days.filter { Double($0.sleep_minutes) > mean + 1.2 * sd }
        let lo = days.filter { $0.sleep_minutes > 0 && Double($0.sleep_minutes) < mean - 1.2 * sd }
        return (hi, lo)
    }

    private func formatDay(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter()
        o.dateFormat = "dd.MM"
        o.locale = Locale(identifier: "ru_RU")
        return o.string(from: d)
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 60) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Тренд 30 дней + среднее (rolling)

struct TrackerSleepTrendReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let points = Self.lastDays(s.daily_breakdown, count: 30)
                let avg = Self.rollingAverage(points, window: 7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if #available(iOS 17.0, *) {
                            Chart {
                                ForEach(points, id: \.date) { d in
                                    LineMark(
                                        x: .value("Дата", formatDay(d.date)),
                                        y: .value("Минуты", d.sleep_minutes)
                                    )
                                    .foregroundStyle(FamilyAppStyle.accent.opacity(0.35))
                                    PointMark(
                                        x: .value("Дата", formatDay(d.date)),
                                        y: .value("Минуты", d.sleep_minutes)
                                    )
                                    .foregroundStyle(FamilyAppStyle.accent.opacity(0.6))
                                }
                                ForEach(avg, id: \.date) { d in
                                    LineMark(
                                        x: .value("Дата", formatDay(d.date)),
                                        y: .value("Среднее7", d.sleep_minutes)
                                    )
                                    .foregroundStyle(FamilyAppStyle.accent)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                }
                            }
                            .frame(height: 240)
                        }

                        let perDay = points.isEmpty ? 0 : points.map(\.sleep_minutes).reduce(0, +) / max(1, points.count)
                        Text("Средне за сутки (последние \(points.count) дней с данными): \(AnalyticsFormatters.sleepDuration(perDay))")
                            .font(.footnote)
                            .foregroundStyle(FamilyAppStyle.captionMuted)

                        Text("Тонкая линия — фактический сон по дням, жирная — сглаживание (среднее за 7 дней).")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Тренд сна")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func formatDay(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter()
        o.dateFormat = "dd.MM"
        o.locale = Locale(identifier: "ru_RU")
        return o.string(from: d)
    }

    private static func lastDays(_ days: [DailyStat], count: Int) -> [DailyStat] {
        let sorted = days.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
        return Array(sorted.suffix(max(1, count)))
    }

    private struct AvgPoint {
        let date: String
        let sleep_minutes: Int
    }

    private static func rollingAverage(_ days: [DailyStat], window: Int) -> [AvgPoint] {
        guard window >= 2, days.count >= window else { return [] }
        var out: [AvgPoint] = []
        for i in (window - 1)..<days.count {
            let slice = days[(i - (window - 1))...i]
            let v = slice.map(\.sleep_minutes).reduce(0, +) / window
            out.append(AvgPoint(date: days[i].date, sleep_minutes: v))
        }
        return out
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 60) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Распределение сна (гистограмма по диапазонам)

struct TrackerSleepDistributionReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let rows = Self.buckets(from: s.daily_breakdown)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if #available(iOS 17.0, *) {
                            Chart(rows, id: \.name) { row in
                                BarMark(
                                    x: .value("Диапазон", row.name),
                                    y: .value("Дней", row.days)
                                )
                                .foregroundStyle(FamilyAppStyle.accent.gradient)
                            }
                            .frame(height: 220)
                        }
                        VStack(spacing: 8) {
                            ForEach(rows, id: \.name) { r in
                                HStack {
                                    Text(r.name)
                                    Spacer()
                                    Text("\(r.days)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Гистограмма помогает понять, насколько часто сон попадает в «нормальный» диапазон и как распределены дни.")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Распределение сна")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct BucketRow {
        let name: String
        let days: Int
    }

    private static func bucketName(_ minutes: Int) -> String {
        if minutes < 300 { return "<5ч" }
        if minutes < 390 { return "5–6.5ч" }
        if minutes < 480 { return "6.5–8ч" }
        if minutes < 600 { return "8–10ч" }
        return "10ч+"
    }

    private static func buckets(from days: [DailyStat]) -> [BucketRow] {
        let vals = days.map(\.sleep_minutes).filter { $0 > 0 }
        var counts: [String: Int] = [:]
        for v in vals { counts[bucketName(v), default: 0] += 1 }
        let order = ["<5ч", "5–6.5ч", "6.5–8ч", "8–10ч", "10ч+"]
        return order.map { BucketRow(name: $0, days: counts[$0, default: 0]) }
            .filter { $0.days > 0 }
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 60) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}
