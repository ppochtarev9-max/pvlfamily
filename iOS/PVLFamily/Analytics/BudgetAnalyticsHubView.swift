import SwiftUI

/// DATA-04: хаб отчётов по бюджету — сводка «сегодня / месяц» + список пресетов.
struct BudgetAnalyticsHubView: View {
    @EnvironmentObject var authManager: AuthManager

    let initialUserId: Int?

    @State private var selectedUserId: Int?
    @State private var selectedDateFilter: BudgetView.DateFilter = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var selectedGroupId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil

    @State private var todaySummary: DashboardSummary?
    @State private var monthStats: MonthlyStats?
    @State private var previousMonthStats: MonthlyStats?
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
                            BudgetTopExpenseCategoriesView(userId: selectedUserId)
                        } label: {
                            Label("Топ категорий расхода (месяц)", systemImage: "list.number")
                        }
                        NavigationLink {
                            BudgetMonthOverMonthView(userId: selectedUserId)
                        } label: {
                            Label("Сравнение с прошлым месяцем", systemImage: "arrow.left.arrow.right")
                        }
                        NavigationLink {
                            BudgetThreeMonthAverageView(userId: selectedUserId)
                        } label: {
                            Label("Средние за 3 месяца", systemImage: "function")
                        }
                        NavigationLink {
                            BudgetSixMonthStripView(userId: selectedUserId)
                        } label: {
                            Label("6 месяцев: сальдо (тренд-таблица)", systemImage: "tablecells")
                        }
                    } header: { Text("Тренды и сравнения") }

                    Section {
                        NavigationLink {
                            BudgetDetailsView(
                                selectedUserId: $selectedUserId,
                                selectedDateFilter: $selectedDateFilter,
                                customStartDate: $customStartDate,
                                customEndDate: $customEndDate,
                                selectedGroupId: $selectedGroupId,
                                selectedSubcategoryId: $selectedSubcategoryId
                            )
                        } label: {
                            Label("Детализация по категориям (месяц)", systemImage: "chart.pie.fill")
                        }
                        NavigationLink { ExportDataView() } label: {
                            Label("Экспорт в Excel", systemImage: "square.and.arrow.up")
                        }
                    } header: { Text("Детализация и выгрузка") }

                    Section {
                        NavigationLink { BudgetAnomaliesScaffoldView() } label: {
                            Label("Крупные операции (скоро)", systemImage: "exclamationmark.triangle")
                        }
                        NavigationLink { BudgetCustomPeriodScaffoldView() } label: {
                            Label("Свой период (скоро)", systemImage: "calendar.badge.clock")
                        }
                    } header: { Text("Продвинутое") }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Аналитика")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedUserId == nil { selectedUserId = initialUserId }
            loadSnapshot()
        }
    }

    private var snapshotBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сводка")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FamilyAppStyle.captionMuted)

            if let s = todaySummary {
                snapshotCard(
                    title: "На сегодня",
                    primary: formatMoney(s.balance),
                    secondary: nil,
                    caption: llmTodaySummary ?? BudgetInsightBuilder.todayLine(balance: s.balance),
                    aiPlaceholder: true
                )
            }

            if let m = monthStats {
                snapshotCard(
                    title: monthTitle(m),
                    primary: "Расходы \(formatMoney(abs(m.total_expense)))",
                    secondary: "Доходы \(formatMoney(m.total_income))",
                    caption: llmMonthSummary ?? BudgetInsightBuilder.monthLine(current: m, previous: previousMonthStats),
                    aiPlaceholder: true
                )
            }
            if let llmProviderLabel {
                Text("LLM: \(llmProviderLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func monthTitle(_ m: MonthlyStats) -> String {
        let names = ["", "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
        let name = m.month >= 1 && m.month <= 12 ? names[m.month] : "\(m.month)"
        return "Месяц: \(name) \(m.year)"
    }

    private func snapshotCard(title: String, primary: String, secondary: String? = nil, caption: String, aiPlaceholder: Bool = false) -> some View {
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
                .fixedSize(horizontal: false, vertical: true)
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

    private func formatMoney(_ v: Double) -> String {
        let n = Int(v.rounded())
        let s = String(format: "%d", abs(n))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out = " " + out }
            out = String(c) + out
        }
        return (n < 0 ? "−" : "") + out + " ₽"
    }

    private func loadSnapshot() {
        isLoading = true
        loadError = nil
        let uid = selectedUserId
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let dayStr = f.string(from: now)

        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        var py = y
        var pm = m - 1
        if pm < 1 { pm = 12; py -= 1 }

        let group = DispatchGroup()
        var today: DashboardSummary?
        var curMonth: MonthlyStats?
        var prevMonth: MonthlyStats?
        var blockError: String?

        group.enter()
        authManager.getDashboardSummary(asOfDate: dayStr, userId: uid) { r in
            defer { group.leave() }
            switch r {
            case .success(let s): today = s
            case .failure(let e): blockError = e.localizedDescription
            }
        }

        group.enter()
        authManager.getMonthlyStats(year: y, month: m, userId: uid) { r in
            defer { group.leave() }
            switch r {
            case .success(let s): curMonth = s
            case .failure(let e):
                if blockError == nil { blockError = e.localizedDescription }
            }
        }

        group.enter()
        authManager.getMonthlyStats(year: py, month: pm, userId: uid) { r in
            defer { group.leave() }
            if case .success(let s) = r { prevMonth = s }
        }

        group.notify(queue: .main) {
            isLoading = false
            if today == nil || curMonth == nil {
                loadError = blockError ?? "Не удалось получить сводку"
                return
            }
            todaySummary = today
            monthStats = curMonth
            previousMonthStats = prevMonth
            requestBudgetInsight(today: today, month: curMonth, previous: prevMonth)
        }
    }

    private func requestBudgetInsight(today: DashboardSummary?, month: MonthlyStats?, previous: MonthlyStats?) {
        guard let today, let month else { return }
        let deltaExpensePct: Double
        if let previous, abs(previous.total_expense) > 0 {
            deltaExpensePct = (abs(month.total_expense) - abs(previous.total_expense)) / abs(previous.total_expense) * 100
        } else {
            deltaExpensePct = 0
        }
        let payload = InsightPayload(
            report_type: "budget",
            period: "current_month",
            metrics: [
                "balance_today": today.balance,
                "income_month": month.total_income,
                "expense_month": abs(month.total_expense),
                "expense_delta_vs_prev_pct": deltaExpensePct
            ],
            trend_flags: [
                today.balance >= 0 ? "balance_positive" : "balance_negative",
                deltaExpensePct > 5 ? "expense_up" : "expense_stable"
            ],
            anomalies: [],
            notes: "safe_payload_only"
        )
        authManager.getInsight(kind: "budget", payload: payload, provider: nil) { result in
            DispatchQueue.main.async {
                guard case .success(let insight) = result else { return }
                llmTodaySummary = insight.summary_today
                llmMonthSummary = insight.summary_month
                llmProviderLabel = insight.provider
            }
        }
    }
}

#Preview {
    NavigationStack {
        BudgetAnalyticsHubView(initialUserId: nil)
            .environmentObject(AuthManager())
    }
}
