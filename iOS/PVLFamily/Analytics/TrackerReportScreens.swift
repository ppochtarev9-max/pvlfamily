import SwiftUI
import Foundation
import Charts

private enum TrackerReportDateFormatters {
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

    static func dayLabel(from iso: String) -> String {
        guard let d = isoDay.date(from: iso) else { return iso }
        return dayLabelRU.string(from: d)
    }
}

// MARK: - Сон vs Бодрствование (по дням)

struct TrackerSleepWakeDailyReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var windowDays: Int = 30
    
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let dayLabelFormatterRU: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let points = Self.lastDays(s.daily_breakdown, count: windowDays)
                let kpi = Self.kpi(from: points)
                let chartPoints = Self.toSeriesPoints(points)
                reportScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Окно", selection: $windowDays) {
                            Text("7д").tag(7)
                            Text("10д").tag(10)
                            Text("30д").tag(30)
                            Text("60д").tag(60)
                            Text("90д").tag(90)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowDays) { _, _ in load() }

                        kpiBlock(kpi: kpi)

                        if #available(iOS 17.0, *) {
                            Chart {
                                ForEach(chartPoints, id: \.id) { p in
                                    LineMark(
                                        x: .value("Дата", p.dateLabel),
                                        y: .value("Минуты", p.minutes)
                                    )
                                    .foregroundStyle(by: .value("Серия", p.series))
                                    .lineStyle(p.series == "Бодрствование"
                                               ? StrokeStyle(lineWidth: 2.5, dash: [6, 4])
                                               : StrokeStyle(lineWidth: 2.5))
                                    .symbol(p.series == "Бодрствование" ? .square : .circle)
                                    .symbolSize(p.series == "Бодрствование" ? 38 : 30)
                                }
                            }
                            .chartForegroundStyleScale([
                                "Сон": FamilyAppStyle.accent,
                                "Бодрствование": FamilyAppStyle.expenseCoral
                            ])
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 240)
                        }

                        Text("Бодрствование считается как 1440 − сон (в минутах). Пунктир — бодрствование.")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Сон vs Бодрствование")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct KPI {
        let avgSleep: Int
        let avgWake: Int
        let sleepShare: Double
        let days: Int
    }

    private static func lastDays(_ days: [DailyStat], count: Int) -> [DailyStat] {
        let sorted = days.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
        return Array(sorted.suffix(max(1, count)))
    }
    
    private struct ChartPoint {
        let dateLabel: String
        let series: String
        let minutes: Int
        var id: String { "\(dateLabel)-\(series)" }
    }
    
    private static func toSeriesPoints(_ days: [DailyStat]) -> [ChartPoint] {
        var out: [ChartPoint] = []
        out.reserveCapacity(days.count * 2)
        for d in days {
            let dateLabel: String
            if let date = isoDateFormatter.date(from: d.date) {
                dateLabel = dayLabelFormatterRU.string(from: date)
            } else {
                dateLabel = d.date
            }
            let sleep = max(0, d.sleep_minutes)
            let wake = max(0, 1440 - sleep)
            out.append(.init(dateLabel: dateLabel, series: "Сон", minutes: sleep))
            out.append(.init(dateLabel: dateLabel, series: "Бодрствование", minutes: wake))
        }
        return out
    }

    private static func kpi(from days: [DailyStat]) -> KPI {
        let vals = days.filter { $0.sleep_minutes > 0 }
        let n = max(1, vals.count)
        let totalSleep = vals.map(\.sleep_minutes).reduce(0, +)
        let totalWake = vals.map { max(0, 1440 - $0.sleep_minutes) }.reduce(0, +)
        let avgSleep = totalSleep / n
        let avgWake = totalWake / n
        let denom = max(1, totalSleep + totalWake)
        let share = Double(totalSleep) / Double(denom)
        return KPI(avgSleep: avgSleep, avgWake: avgWake, sleepShare: share, days: vals.count)
    }

    private func kpiBlock(kpi: KPI) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                kpiCard(title: "Средний сон", value: kpi.days > 0 ? AnalyticsFormatters.sleepDuration(kpi.avgSleep) : "—")
                kpiCard(title: "Среднее бодрств.", value: kpi.days > 0 ? AnalyticsFormatters.sleepDuration(kpi.avgWake) : "—")
            }
            HStack(alignment: .top) {
                kpiCard(title: "Доля сна", value: kpi.days > 0 ? percent(kpi.sleepShare) : "—")
                kpiCard(title: "Дней с данными", value: "\(kpi.days)")
            }
        }
    }

    private func kpiCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
    }

    private func percent(_ v: Double) -> String {
        let p = Int((v * 100).rounded())
        return "\(p)%"
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
        authManager.getTrackerStats(days: windowDays) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Сравнение окон: последние 7 vs предыдущие 7

struct TrackerSleepWake7v7ReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let ordered = s.daily_breakdown.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
                let last14 = Array(ordered.suffix(14))
                let prev7 = Array(last14.prefix(7))
                let cur7 = Array(last14.suffix(7))
                let cmp = compare(prev: prev7, cur: cur7)
                reportScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Сравнение средних значений за последние 7 дней и предыдущие 7 дней.")
                            .font(.subheadline)
                            .foregroundStyle(FamilyAppStyle.captionMuted)

                        kpiBlock(cmp: cmp)

                        if #available(iOS 17.0, *) {
                            Chart(cmp.bars, id: \.id) { b in
                                BarMark(
                                    x: .value("Период", b.period),
                                    y: .value("Минуты", b.minutes)
                                )
                                .foregroundStyle(by: .value("Метрика", b.metric))
                                .cornerRadius(4)
                            }
                            .chartForegroundStyleScale([
                                "Сон": FamilyAppStyle.accent,
                                "Бодрствование": FamilyAppStyle.captionMuted
                            ])
                            .frame(height: 220)
                        }

                        Text("Бодрствование считается как 1440 − сон. Дельты показаны как «последние 7» минус «предыдущие 7».")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("7 дней vs 7 дней")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct Comparison {
        let prevAvgSleep: Int
        let curAvgSleep: Int
        let deltaAvgSleep: Int
        let prevAvgWake: Int
        let curAvgWake: Int
        let deltaAvgWake: Int
        let bars: [Bar]
    }

    private struct Bar: Identifiable {
        let period: String
        let metric: String
        let minutes: Int
        var id: String { "\(period)-\(metric)" }
    }

    private func compare(prev: [DailyStat], cur: [DailyStat]) -> Comparison {
        let pN = max(1, prev.count)
        let cN = max(1, cur.count)
        let pSleep = prev.map(\.sleep_minutes).reduce(0, +)
        let cSleep = cur.map(\.sleep_minutes).reduce(0, +)
        let pWake = prev.map { max(0, 1440 - $0.sleep_minutes) }.reduce(0, +)
        let cWake = cur.map { max(0, 1440 - $0.sleep_minutes) }.reduce(0, +)

        let pAvgSleep = pSleep / pN
        let cAvgSleep = cSleep / cN
        let pAvgWake = pWake / pN
        let cAvgWake = cWake / cN

        let bars: [Bar] = [
            .init(period: "пред. 7", metric: "Сон", minutes: pAvgSleep),
            .init(period: "посл. 7", metric: "Сон", minutes: cAvgSleep),
            .init(period: "пред. 7", metric: "Бодрствование", minutes: pAvgWake),
            .init(period: "посл. 7", metric: "Бодрствование", minutes: cAvgWake),
        ]

        return Comparison(
            prevAvgSleep: pAvgSleep,
            curAvgSleep: cAvgSleep,
            deltaAvgSleep: cAvgSleep - pAvgSleep,
            prevAvgWake: pAvgWake,
            curAvgWake: cAvgWake,
            deltaAvgWake: cAvgWake - pAvgWake,
            bars: bars
        )
    }

    private func kpiBlock(cmp: Comparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                kpiCard(
                    title: "Сон (сред.)",
                    value: "\(AnalyticsFormatters.sleepDuration(cmp.curAvgSleep))",
                    delta: deltaString(cmp.deltaAvgSleep)
                )
                kpiCard(
                    title: "Бодрств. (сред.)",
                    value: "\(AnalyticsFormatters.sleepDuration(cmp.curAvgWake))",
                    delta: deltaString(cmp.deltaAvgWake)
                )
            }
        }
    }

    private func deltaString(_ minutes: Int) -> String {
        let sign = minutes >= 0 ? "+" : "−"
        return "\(sign)\(AnalyticsFormatters.sleepDuration(abs(minutes)))"
    }

    private func kpiCard(title: String, value: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text("Δ \(delta)")
                .font(.caption2)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
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

// MARK: - Сравнение двух последних недель

struct TrackerCompareWeeksReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var weeks: Int = 2

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
        let parts = splitWindow(s.daily_breakdown, weeks: weeks)
        let diff = parts.1 - parts.0
        reportScroll {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Сравнение: предыдущие \(weeks * 7) дней vs последние \(weeks * 7) дней (по дате).")
                        .font(.subheadline)
                        .foregroundStyle(FamilyAppStyle.captionMuted)
                    Picker("Окно", selection: $weeks) {
                        Text("2 недели").tag(2)
                        Text("4 недели").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: weeks) { _, _ in load() }
                }
                HStack(alignment: .top) {
                    weekColumn(title: "Раньше", minutes: parts.0, days: weeks * 7)
                    weekColumn(title: "Позже", minutes: parts.1, days: weeks * 7)
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
        splitWindow(days, weeks: 2)
    }

    private func splitWindow(_ days: [DailyStat], weeks: Int) -> (Int, Int) {
        let sorted = days.sorted { $0.date < $1.date }
        let n = max(1, weeks * 7)
        let first = Array(sorted.prefix(n))
        let last = Array(sorted.suffix(min(n, sorted.count)))
        return (
            first.map(\.sleep_minutes).reduce(0, +),
            last.map(\.sleep_minutes).reduce(0, +)
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
        authManager.getTrackerStats(days: weeks * 14) { r in
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
    @State private var shortDays: Int = 7
    @State private var longDays: Int = 30

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Выберите окна для сравнения средних значений.")
                                .font(.subheadline)
                                .foregroundStyle(FamilyAppStyle.captionMuted)
                            HStack(spacing: 12) {
                                Picker("Короткое", selection: $shortDays) {
                                    Text("7д").tag(7)
                                    Text("14д").tag(14)
                                    Text("30д").tag(30)
                                }
                                .pickerStyle(.segmented)
                                Picker("Длинное", selection: $longDays) {
                                    Text("30д").tag(30)
                                    Text("60д").tag(60)
                                    Text("90д").tag(90)
                                }
                                .pickerStyle(.segmented)
                            }
                            .onChange(of: shortDays) { _, _ in load() }
                            .onChange(of: longDays) { _, _ in load() }
                        }
                        if #available(iOS 17.0, *) {
                            Chart(avgBars(), id: \.period) { item in
                                BarMark(
                                    x: .value("Период", item.period),
                                    y: .value("Минуты", item.perDay)
                                )
                                .foregroundStyle(item.period == "\(shortDays)д" ? FamilyAppStyle.accent : FamilyAppStyle.captionMuted)
                            }
                            .frame(height: 180)
                        }
                        if let a = s7, a.total_sessions > 0 {
                            row("\(shortDays) дней", avg: a.total_sleep_minutes / a.total_sessions, perDay: a.total_sleep_minutes / max(1, shortDays))
                        }
                        if let b = s30, b.total_sessions > 0 {
                            row("\(longDays) дней", avg: b.total_sleep_minutes / b.total_sessions, perDay: b.total_sleep_minutes / max(1, longDays))
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
        if let a = s7 { rows.append(("\(shortDays)д", a.total_sleep_minutes / max(1, shortDays))) }
        if let b = s30 { rows.append(("\(longDays)д", b.total_sleep_minutes / max(1, longDays))) }
        return rows
    }

    private func load() {
        isLoading = true
        let g = DispatchGroup()
        g.enter()
        authManager.getTrackerStats(days: shortDays) { r in defer { g.leave() }; if case .success(let s) = r { s7 = s } }
        g.enter()
        authManager.getTrackerStats(days: longDays) { r in defer { g.leave() }; if case .success(let s) = r { s30 = s } }
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
    @State private var windowDays: Int = 60

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let out = Self.outliers(from: s.daily_breakdown)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Окно", selection: $windowDays) {
                            Text("7д").tag(7)
                            Text("10д").tag(10)
                            Text("30д").tag(30)
                            Text("60д").tag(60)
                            Text("90д").tag(90)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowDays) { _, _ in load() }
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
        TrackerReportDateFormatters.dayLabel(from: iso)
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: windowDays) { r in
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
    @State private var windowDays: Int = 60

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let points = Self.lastDays(s.daily_breakdown, count: windowDays)
                let avg = Self.rollingAverage(points, window: 7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Окно", selection: $windowDays) {
                            Text("7д").tag(7)
                            Text("10д").tag(10)
                            Text("30д").tag(30)
                            Text("60д").tag(60)
                            Text("90д").tag(90)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowDays) { _, _ in load() }
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
        TrackerReportDateFormatters.dayLabel(from: iso)
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
        authManager.getTrackerStats(days: windowDays) { r in
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
    @State private var windowDays: Int = 60

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let rows = Self.buckets(from: s.daily_breakdown)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Окно", selection: $windowDays) {
                            Text("7д").tag(7)
                            Text("10д").tag(10)
                            Text("30д").tag(30)
                            Text("60д").tag(60)
                            Text("90д").tag(90)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowDays) { _, _ in load() }
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
        authManager.getTrackerStats(days: windowDays) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Дневной vs Ночной (разрез по kind)

struct TrackerDayNightReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var windowDays: Int = 60

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let total = totals(from: s, windowDays: windowDays)
                if total.totalDay == 0, total.totalNight == 0, total.hasSplitData == false {
                    ContentUnavailableView(
                        "Нет разреза «дневной/ночной»",
                        systemImage: "moon.circle",
                        description: Text("Похоже, сервер ещё не отдаёт разметку сна по типу. Обновите сервер и перезагрузите приложение, либо проверьте, что в базе проставляется kind для эпизодов.")
                    )
                } else {
                    reportScroll {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Окно", selection: $windowDays) {
                                Text("7д").tag(7)
                                Text("10д").tag(10)
                                Text("30д").tag(30)
                                Text("60д").tag(60)
                                Text("90д").tag(90)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: windowDays) { _, _ in load() }

                            kpiBlock(total: total)

                            if #available(iOS 17.0, *) {
                                Chart(chartPoints(from: s.daily_breakdown), id: \.id) { p in
                                    BarMark(
                                        x: .value("Дата", p.dayLabel),
                                        y: .value("Минуты", p.minutes)
                                    )
                                    .foregroundStyle(by: .value("Сон", p.kindLabel))
                                    .cornerRadius(3)
                                }
                                .chartForegroundStyleScale([
                                    "Ночной": FamilyAppStyle.accent,
                                    "Дневной": FamilyAppStyle.captionMuted
                                ])
                                .frame(height: 240)
                            }

                            Text("График показывает разрез по дням: ночной и дневной сон. Если в какие-то дни разметки нет, они будут отображаться как нули.")
                                .font(.caption2)
                                .foregroundStyle(FamilyAppStyle.captionMuted)
                        }
                    }
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Дневной vs Ночной")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct Totals {
        let totalDay: Int
        let totalNight: Int
        let nightShare: Double
        let dayAvg: Int
        let nightAvg: Int
        let hasSplitData: Bool
    }

    private func totals(from s: TrackerStats, windowDays: Int) -> Totals {
        let fromTotalsDay = s.total_day_sleep_minutes
        let fromTotalsNight = s.total_night_sleep_minutes

        let summedDay = s.daily_breakdown.map { $0.day_sleep_minutes ?? 0 }.reduce(0, +)
        let summedNight = s.daily_breakdown.map { $0.night_sleep_minutes ?? 0 }.reduce(0, +)

        let day = fromTotalsDay ?? summedDay
        let night = fromTotalsNight ?? summedNight

        let denom = max(1, day + night)
        let share = Double(night) / Double(denom)

        let avgDay = day / max(1, windowDays)
        let avgNight = night / max(1, windowDays)

        let hasAnySplit = s.daily_breakdown.contains { ($0.day_sleep_minutes != nil) || ($0.night_sleep_minutes != nil) }
            || (fromTotalsDay != nil) || (fromTotalsNight != nil)

        return Totals(
            totalDay: day,
            totalNight: night,
            nightShare: share,
            dayAvg: avgDay,
            nightAvg: avgNight,
            hasSplitData: hasAnySplit
        )
    }

    private func kpiBlock(total: Totals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                kpiCard(title: "Ночной (Σ)", value: AnalyticsFormatters.sleepDuration(total.totalNight))
                kpiCard(title: "Дневной (Σ)", value: AnalyticsFormatters.sleepDuration(total.totalDay))
            }
            HStack(alignment: .top) {
                kpiCard(title: "Доля ночного", value: percent(total.nightShare))
                kpiCard(title: "Средне за сутки", value: "\(AnalyticsFormatters.sleepDuration(total.nightAvg)) / \(AnalyticsFormatters.sleepDuration(total.dayAvg))")
            }
        }
    }

    private func kpiCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
    }

    private func percent(_ v: Double) -> String {
        let p = Int((v * 100).rounded())
        return "\(p)%"
    }

    private struct DayNightBarPoint: Identifiable {
        enum Kind: String { case night, day }
        let dayLabel: String
        let kind: Kind
        let minutes: Int
        var id: String { "\(dayLabel)-\(kind.rawValue)" }
        var kindLabel: String { kind == .night ? "Ночной" : "Дневной" }
    }

    private func chartPoints(from days: [DailyStat]) -> [DayNightBarPoint] {
        let sorted = days.sorted { $0.date < $1.date }
        let last = Array(sorted.suffix(max(1, windowDays)))
        var out: [DayNightBarPoint] = []
        out.reserveCapacity(last.count * 2)
        for d in last {
            let dayLabel = formatDay(d.date)
            out.append(.init(dayLabel: dayLabel, kind: .night, minutes: d.night_sleep_minutes ?? 0))
            out.append(.init(dayLabel: dayLabel, kind: .day, minutes: d.day_sleep_minutes ?? 0))
        }
        return out
    }

    private func formatDay(_ iso: String) -> String {
        TrackerReportDateFormatters.dayLabel(from: iso)
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
        authManager.getTrackerStats(days: windowDays) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Полная аналитика дня (24 часа)

struct TrackerFullDayAnalytics24hReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var windowDays: Int = 30

    private static func lastDaysWithData(_ days: [DailyStat], count: Int) -> [DailyStat] {
        let sorted = days.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
        return Array(sorted.suffix(max(1, count)))
    }

    private struct BarPoint: Identifiable {
        let dayLabel: String
        let series: String
        let minutes: Int
        var id: String { "\(dayLabel)-\(series)" }
    }

    private struct LinePoint: Identifiable {
        let dayLabel: String
        let series: String
        let minutes: Int
        var id: String { "\(dayLabel)-\(series)" }
    }

    private func barPoints(from days: [DailyStat]) -> [BarPoint] {
        var out: [BarPoint] = []
        out.reserveCapacity(days.count * 2)
        for d in days {
            let label = TrackerReportDateFormatters.dayLabel(from: d.date)
            let sleep = max(0, d.sleep_minutes)
            let wake = max(0, 1440 - sleep)
            out.append(.init(dayLabel: label, series: "Сон", minutes: sleep))
            out.append(.init(dayLabel: label, series: "Бодрствование", minutes: wake))
        }
        return out
    }

    private func linePoints(from days: [DailyStat]) -> [LinePoint] {
        days.map { d in
            .init(
                dayLabel: TrackerReportDateFormatters.dayLabel(from: d.date),
                series: "Тренд (сон)",
                minutes: max(0, d.sleep_minutes)
            )
        }
    }

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let days = Self.lastDaysWithData(s.daily_breakdown, count: windowDays)
                let bars = barPoints(from: days)
                let line = linePoints(from: days)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Окно", selection: $windowDays) {
                            Text("7д").tag(7)
                            Text("10д").tag(10)
                            Text("30д").tag(30)
                            Text("60д").tag(60)
                            Text("90д").tag(90)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowDays) { _, _ in load() }

                        if #available(iOS 17.0, *) {
                            Chart {
                                ForEach(bars) { p in
                                    BarMark(
                                        x: .value("Дата", p.dayLabel),
                                        y: .value("Минуты", p.minutes)
                                    )
                                    .foregroundStyle(by: .value("Серия", p.series))
                                    .position(by: .value("Тип", "24h"), axis: .horizontal)
                                    .cornerRadius(3)
                                }
                                ForEach(line) { p in
                                    LineMark(
                                        x: .value("Дата", p.dayLabel),
                                        y: .value("Минуты", p.minutes)
                                    )
                                    .foregroundStyle(by: .value("Серия", p.series))
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    .symbol(.circle)
                                    .symbolSize(26)
                                }
                            }
                            .chartYScale(domain: 0...1440)
                            .chartForegroundStyleScale([
                                "Сон": FamilyAppStyle.accent,
                                "Бодрствование": FamilyAppStyle.expenseCoral,
                                "Тренд (сон)": FamilyAppStyle.pixsoInk.opacity(0.65)
                            ])
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 260)
                        }

                        Text("Каждый столбик — 24 часа: сон и бодрствование (1440 − сон). Линия — тренд сна по дням.")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Полная аналитика дня")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: windowDays) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}
