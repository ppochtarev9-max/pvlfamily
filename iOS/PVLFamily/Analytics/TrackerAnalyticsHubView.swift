import SwiftUI
import Foundation

/// DATA-04: аналитика трекера — сводка «сегодня / месяц» + пресеты отчётов.
struct TrackerAnalyticsHubView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var todayStats: TrackerStats?
    @State private var longStats: TrackerStats?
    @State private var llmTodaySummary: String?
    @State private var llmMonthSummary: String?
    @State private var llmProviderLabel: String?
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
                        NavigationLink { TrackerCompareWeeksReportView() } label: {
                            Label("Сравнение двух недель", systemImage: "arrow.left.arrow.right")
                        }
                        NavigationLink { TrackerAveragesReportView() } label: {
                            Label("Средний сон: 7 и 30 дней", systemImage: "function")
                        }
                    } header: { Text("Тренды и сравнения") }

                    Section {
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
                snapshotCard(
                    title: "На сегодня (завершённый сон)",
                    primary: AnalyticsFormatters.sleepDuration(m),
                    secondary: "Эпизодов: \(ses)",
                    caption: llmTodaySummary ?? TrackerSleepInsightBuilder.todayLine(sleepMinutes: m, sessions: ses),
                    aiPlaceholder: shouldShowAIPlaceholder
                )
            }

            if let slice = thisMonthSlice {
                let avgSession = slice.sessions > 0 ? slice.minutes / slice.sessions : 0
                snapshotCard(
                    title: "В этом месяце",
                    primary: "Всего \(AnalyticsFormatters.sleepDuration(slice.minutes))",
                    secondary: "Дней с данными: \(slice.days) · эпизодов \(slice.sessions)",
                    caption: llmMonthSummary ?? TrackerSleepInsightBuilder.monthLine(
                        totalMinutes: slice.minutes,
                        daysWithData: slice.days,
                        averagePerSession: avgSession
                    ),
                    aiPlaceholder: shouldShowAIPlaceholder
                )
            }
            if let llmProviderLabel {
                Text("LLM: \(llmProviderLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var shouldShowAIPlaceholder: Bool {
        guard let provider = llmProviderLabel?.lowercased(), !provider.isEmpty else { return true }
        return provider.contains("fallback")
    }

    private var thisMonthSlice: (minutes: Int, days: Int, sessions: Int)? {
        guard let s = longStats else { return nil }
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        var min = 0, days = 0, ses = 0
        for d in s.daily_breakdown {
            let parts = d.date.split(separator: "-")
            guard parts.count == 3,
                  let yy = Int(parts[0]), let mm = Int(parts[1]) else { continue }
            if yy == y && mm == m {
                min += d.sleep_minutes
                ses += d.sessions_count
                if d.sleep_minutes > 0 { days += 1 }
            }
        }
        return (min, days, ses)
    }

    private func snapshotCard(title: String, primary: String, secondary: String? = nil, caption: String, aiPlaceholder: Bool) -> some View {
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
            if aiPlaceholder {
                Text("— место для рекомендации ИИ —")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.tertiary)
            }
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
            requestTrackerInsight(today: t1, longWindow: t60)
        }
    }

    private func requestTrackerInsight(today: TrackerStats?, longWindow: TrackerStats?) {
        guard let today, let longWindow else { return }
        let month = thisMonthSlice
        let payload = InsightPayload(
            report_type: "tracker",
            period: "current_month",
            metrics: [
                "sleep_today_minutes": Double(today.total_sleep_minutes),
                "sessions_today": Double(today.total_sessions),
                "sleep_month_minutes": Double(month?.minutes ?? 0),
                "days_with_data_month": Double(month?.days ?? 0)
            ],
            trend_flags: [
                (month?.minutes ?? 0) > 0 ? "month_has_data" : "month_no_data",
                today.total_sleep_minutes > 0 ? "day_has_sleep" : "day_no_sleep"
            ],
            anomalies: trackerAnomalies(from: longWindow.daily_breakdown),
            notes: "safe_payload_only"
        )
        authManager.getInsight(kind: "tracker", payload: payload, provider: nil) { result in
            DispatchQueue.main.async {
                guard case .success(let insight) = result else { return }
                llmTodaySummary = insight.summary_today
                llmMonthSummary = insight.summary_month
                llmProviderLabel = insight.provider
            }
        }
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
