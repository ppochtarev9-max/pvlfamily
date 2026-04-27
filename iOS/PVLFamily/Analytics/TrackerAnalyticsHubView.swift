import SwiftUI
import Foundation

/// DATA-04: аналитика трекера — сводка «сегодня / месяц» + пресеты отчётов.
struct TrackerAnalyticsHubView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var todayStats: TrackerStats?
    @State private var longStats: TrackerStats?
    @State private var isAIExpanded = false
    @State private var isAILoading = false
    @State private var hasAttemptedLLM = false
    @State private var llmError: String?
    @State private var llmTodaySummary: String?
    @State private var llmMonthSummary: String?
    @State private var llmBullets: [String] = []
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

                    if isAIExpanded {
                        Section {
                            aiInsightPanel
                        } header: {
                            Text("Рекомендация ИИ")
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isAIExpanded {
                        isAIExpanded = false
                    } else {
                        isAIExpanded = true
                        if !hasAttemptedLLM { runTrackerLLMRequest() }
                    }
                } label: {
                    Label("ИИ-вывод", systemImage: isAIExpanded ? "chevron.up" : "sparkles")
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
                snapshotCard(
                    title: "На сегодня (завершённый сон)",
                    primary: AnalyticsFormatters.sleepDuration(m),
                    secondary: "Эпизодов: \(ses)",
                    caption: TrackerSleepInsightBuilder.todayLine(sleepMinutes: m, sessions: ses)
                )
            }

            if let slice = thisMonthSlice {
                let avgSession = slice.sessions > 0 ? slice.minutes / slice.sessions : 0
                snapshotCard(
                    title: "В этом месяце",
                    primary: "Всего \(AnalyticsFormatters.sleepDuration(slice.minutes))",
                    secondary: "Дней с данными: \(slice.days) · эпизодов \(slice.sessions)",
                    caption: TrackerSleepInsightBuilder.monthLine(
                        totalMinutes: slice.minutes,
                        daysWithData: slice.days,
                        averagePerSession: avgSession
                    )
                )
            }
            Text("ИИ: нажмите «ИИ-вывод» вверху, чтобы получить развёрнутый анализ.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var aiInsightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAILoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Запрос к ИИ…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let err = llmError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if hasAttemptedLLM {
                if let t = llmTodaySummary, !t.isEmpty {
                    Text("Сегодня")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FamilyAppStyle.captionMuted)
                    Text(t)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                if let m = llmMonthSummary, !m.isEmpty {
                    Text("В этом месяце")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FamilyAppStyle.captionMuted)
                        .padding(.top, 4)
                    Text(m)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                if !llmBullets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(llmBullets.enumerated()), id: \.offset) { _, line in
                            Text("• \(line)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                if let p = llmProviderLabel, !p.isEmpty {
                    Text("Источник: \(p)\(p.lowercased().contains("fallback") ? " (резервные правила)" : "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            if hasAttemptedLLM, !isAILoading {
                Button("Обновить ответ ИИ") {
                    runTrackerLLMRequest(force: true)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
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

    private func runTrackerLLMRequest(force: Bool = false) {
        guard let today = todayStats, let longWindow = longStats else { return }
        if isAILoading { return }
        if !force, hasAttemptedLLM { return }
        isAILoading = true
        if force { llmError = nil }
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
                isAILoading = false
                hasAttemptedLLM = true
                switch result {
                case .success(let insight):
                    llmError = nil
                    llmTodaySummary = insight.summary_today
                    llmMonthSummary = insight.summary_month
                    llmBullets = insight.bullets
                    llmProviderLabel = insight.provider
                case .failure(let err):
                    llmError = err.localizedDescription
                }
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
