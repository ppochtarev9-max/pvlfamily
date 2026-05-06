import SwiftUI
import Foundation

/// DATA-04: аналитика трекера — сводка «сегодня / месяц» + пресеты отчётов.
struct TrackerAnalyticsHubView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var todayStats: TrackerStats?
    @State private var longStats: TrackerStats?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView("Не удалось загрузить", systemImage: "exclamationmark.triangle", description: Text(err))
            } else {
                List {
                    Section {
                        snapshotBlock
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)

                    Section {
                        NavigationLink {
                            TrackerStatsView(embedInNavigationStack: false)
                                .environmentObject(authManager)
                        } label: {
                            Label("Сон по дням (график и KPI)", systemImage: "chart.bar.xaxis")
                        }
                        NavigationLink { TrackerSleepWakeDailyReportView() } label: {
                            Label("Сон vs Бодрствование (по дням)", systemImage: "arrow.up.and.down")
                        }
                        NavigationLink { TrackerSleepWake7v7ReportView() } label: {
                            Label("Сравнение 7 дней vs 7 дней", systemImage: "calendar.badge.clock")
                        }
                        NavigationLink { TrackerDayNightReportView() } label: {
                            Label("Дневной vs Ночной", systemImage: "moon.stars")
                        }
                        NavigationLink { TrackerSleepTrendReportView() } label: {
                            Label("Тренд сна + среднее (30 дней)", systemImage: "chart.xyaxis.line")
                        }
                        NavigationLink { TrackerCompareWeeksReportView() } label: {
                            Label("Сравнение двух недель", systemImage: "arrow.left.arrow.right")
                        }
                        NavigationLink { TrackerAveragesReportView() } label: {
                            Label("Средний сон: 7 и 30 дней", systemImage: "function")
                        }
                    } header: { Text("Тренды и сравнения") }

                    Section {
                        NavigationLink { TrackerSleepDistributionReportView() } label: {
                            Label("Распределение сна (гистограмма)", systemImage: "chart.bar")
                        }
                        NavigationLink { TrackerOutlierDaysReportView() } label: {
                            Label("Дни с необычным сном (выбросы)", systemImage: "flag.checkered.2.crossed")
                        }
                    } header: { Text("Среднее и выбросы") }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Аналитика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrackerAIChatView()
                        .environmentObject(authManager)
                } label: {
                    Label("ИИ", systemImage: "sparkles")
                }
                .disabled(isLoading || loadError != nil)
            }
        }
        .onAppear(perform: loadSnapshot)
    }

    private var snapshotBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сводка")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FamilyAppStyle.captionMuted)

            if let t = todayStats {
                let m = t.total_sleep_minutes
                let ses = t.total_sessions
                let split = splitLine(totalDay: t.total_day_sleep_minutes, totalNight: t.total_night_sleep_minutes)
                snapshotCard(
                    title: "На сегодня (завершённый сон)",
                    primary: AnalyticsFormatters.sleepDuration(m),
                    secondary: split != nil ? "\(split!) · эпизодов \(ses)" : "Эпизодов: \(ses)",
                    caption: TrackerSleepInsightBuilder.todayLine(sleepMinutes: m, sessions: ses)
                )
            }

            if let slice = thisMonthSlice {
                let avgSession = slice.sessions > 0 ? slice.minutes / slice.sessions : 0
                let split = splitLine(totalDay: slice.dayMinutes, totalNight: slice.nightMinutes)
                snapshotCard(
                    title: "В этом месяце",
                    primary: "Всего \(AnalyticsFormatters.sleepDuration(slice.minutes))",
                    secondary: split != nil
                        ? "Дней с данными: \(slice.days) · \(split!) · эпизодов \(slice.sessions)"
                        : "Дней с данными: \(slice.days) · эпизодов \(slice.sessions)",
                    caption: TrackerSleepInsightBuilder.monthLine(
                        totalMinutes: slice.minutes,
                        daysWithData: slice.days,
                        averagePerSession: avgSession
                    )
                )
            }
            Text("ИИ: нажмите «ИИ» вверху, чтобы открыть чат и задать вопрос про сон.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var thisMonthSlice: (minutes: Int, days: Int, sessions: Int, dayMinutes: Int, nightMinutes: Int)? {
        guard let s = longStats else { return nil }
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        var min = 0, days = 0, ses = 0
        var dayMin = 0, nightMin = 0
        for d in s.daily_breakdown {
            let parts = d.date.split(separator: "-")
            guard parts.count == 3,
                  let yy = Int(parts[0]), let mm = Int(parts[1]) else { continue }
            if yy == y && mm == m {
                min += d.sleep_minutes
                ses += d.sessions_count
                dayMin += d.day_sleep_minutes ?? 0
                nightMin += d.night_sleep_minutes ?? 0
                if d.sleep_minutes > 0 { days += 1 }
            }
        }
        return (min, days, ses, dayMin, nightMin)
    }

    private func splitLine(totalDay: Int?, totalNight: Int?) -> String? {
        guard let totalDay, let totalNight, (totalDay + totalNight) > 0 else { return nil }
        return "ночной \(AnalyticsFormatters.sleepDuration(totalNight)) · дневной \(AnalyticsFormatters.sleepDuration(totalDay))"
    }

    private func snapshotCard(title: String, primary: String, secondary: String? = nil, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(primary)
                .font(.title2.weight(.bold))
                .foregroundStyle(FamilyAppStyle.pixsoInk)
            if let secondary {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
    }

    private func loadSnapshot() {
        isLoading = true
        loadError = nil
        let g = DispatchGroup()
        var t1: TrackerStats?
        var t60: TrackerStats?
        var err: String?

        g.enter()
        authManager.getTrackerStats(days: 1) { r in
            defer { g.leave() }
            switch r {
            case .success(let s): t1 = s
            case .failure(let e): err = e.localizedDescription
            }
        }
        g.enter()
        authManager.getTrackerStats(days: 60) { r in
            defer { g.leave() }
            switch r {
            case .success(let s): t60 = s
            case .failure(let e): if err == nil { err = e.localizedDescription }
            }
        }
        g.notify(queue: .main) {
            isLoading = false
            if t1 == nil && t60 == nil {
                loadError = err ?? "Нет данных"
                return
            }
            todayStats = t1
            longStats = t60
        }
    }


    private func buildTrackerSeries(from days: [DailyStat]) -> [InsightSeries] {
        // Серия по дням: последние 30 дней (если есть), только дни с данными.
        let ordered = days.sorted { $0.date < $1.date }
        let withData = ordered.filter { $0.sleep_minutes > 0 }
        if withData.isEmpty { return [] }

        let last = Array(withData.suffix(30))
        let points = last.map { InsightPoint(t: $0.date, v: Double($0.sleep_minutes)) }

        // Простейшие средние: 7 и 30 дней.
        let last7 = Array(withData.suffix(7))
        let avg7 = last7.isEmpty ? 0.0 : Double(last7.map(\.sleep_minutes).reduce(0, +)) / Double(last7.count)
        let avg30 = last.isEmpty ? 0.0 : Double(last.map { $0.sleep_minutes }.reduce(0, +)) / Double(last.count)

        return [
            InsightSeries(name: "Сон по дням (мин)", points: points, unit: "minutes"),
            InsightSeries(
                name: "Среднее (последние 7 дней)",
                points: [InsightPoint(t: (last7.last?.date ?? ""), v: avg7)],
                unit: "minutes"
            ),
            InsightSeries(
                name: "Среднее (последние 30 дней)",
                points: [InsightPoint(t: (last.last?.date ?? ""), v: avg30)],
                unit: "minutes"
            ),
        ]
    }

    private func buildTrackerComparisons(from days: [DailyStat]) -> [InsightComparison] {
        let ordered = days.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
        guard ordered.count >= 8 else { return [] }

        let last14 = Array(ordered.suffix(14))
        let prev7 = Array(last14.prefix(7))
        let cur7 = Array(last14.suffix(7))
        guard !prev7.isEmpty, !cur7.isEmpty else { return [] }

        let prevSum = Double(prev7.map(\.sleep_minutes).reduce(0, +))
        let curSum = Double(cur7.map(\.sleep_minutes).reduce(0, +))
        let delta = curSum - prevSum
        let deltaPct = prevSum > 0 ? (delta / prevSum) * 100 : nil

        return [
            InsightComparison(
                name: "Сон: 7 дней vs предыдущие 7",
                a_label: "последние 7",
                a_value: curSum,
                b_label: "предыдущие 7",
                b_value: prevSum,
                delta: delta,
                delta_pct: deltaPct,
                unit: "minutes"
            )
        ]
    }

    private func buildTrackerBreakdowns(from days: [DailyStat]) -> [InsightBreakdown] {
        // Распределение длительности сна по диапазонам (только дни с данными).
        let vals = days.map(\.sleep_minutes).filter { $0 > 0 }
        guard vals.count >= 5 else { return [] }

        func bucket(_ minutes: Int) -> String {
            if minutes < 300 { return "<5ч" }
            if minutes < 390 { return "5–6.5ч" }
            if minutes < 480 { return "6.5–8ч" }
            if minutes < 600 { return "8–10ч" }
            return "10ч+"
        }

        var counts: [String: Int] = [:]
        for v in vals { counts[bucket(v), default: 0] += 1 }
        let total = Double(vals.count)

        let order = ["<5ч", "5–6.5ч", "6.5–8ч", "8–10ч", "10ч+"]
        let items: [InsightBreakdownItem] = order.compactMap { name in
            guard let c = counts[name], c > 0 else { return nil }
            return InsightBreakdownItem(name: name, value: Double(c), share: Double(c) / total)
        }
        if items.isEmpty { return [] }
        return [
            InsightBreakdown(name: "Распределение сна по длительности (дни)", items: items, unit: "days")
        ]
    }

    private func trackerAnomalies(from days: [DailyStat]) -> [[String: Double]] {
        let vals = days.filter { $0.sleep_minutes > 0 }.map { Double($0.sleep_minutes) }
        guard vals.count > 2 else { return [] }
        let mean = vals.reduce(0, +) / Double(vals.count)
        let variance = vals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vals.count)
        let sd = sqrt(variance)
        guard sd > 1 else { return [] }
        let highCount = days.filter { Double($0.sleep_minutes) > mean + 1.2 * sd }.count
        let lowCount = days.filter { $0.sleep_minutes > 0 && Double($0.sleep_minutes) < mean - 1.2 * sd }.count
        return [["high_outliers": Double(highCount), "low_outliers": Double(lowCount)]]
    }
}

#Preview {
    NavigationStack {
        TrackerAnalyticsHubView()
            .environmentObject(AuthManager())
    }
}
