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
                            BudgetTopExpenseCategoriesView(userId: selectedUserId)
                        } label: {
                            Label("Топ категорий расхода (месяц)", systemImage: "list.number")
                        }
                        NavigationLink {
                            BudgetExpenseStructureDonutView(userId: selectedUserId)
                        } label: {
                            Label("Структура расходов (месяц)", systemImage: "chart.pie")
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
                        NavigationLink {
                            BudgetSixMonthIncomeExpenseTrendView(userId: selectedUserId)
                        } label: {
                            Label("6 месяцев: доходы/расходы (тренд)", systemImage: "chart.xyaxis.line")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isAIExpanded {
                        isAIExpanded = false
                    } else {
                        isAIExpanded = true
                        if !hasAttemptedLLM { runBudgetLLMRequest() }
                    }
                } label: {
                    Label("ИИ-вывод", systemImage: isAIExpanded ? "chevron.up" : "sparkles")
                }
                .disabled(isLoading || loadError != nil)
            }
        }
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
                    caption: BudgetInsightBuilder.todayLine(balance: s.balance)
                )
            }

            if let m = monthStats {
                snapshotCard(
                    title: monthTitle(m),
                    primary: "Расходы \(formatMoney(abs(m.total_expense)))",
                    secondary: "Доходы \(formatMoney(m.total_income))",
                    caption: BudgetInsightBuilder.monthLine(current: m, previous: previousMonthStats)
                )
            }
            Text("ИИ: нажмите «ИИ-вывод» вверху, чтобы получить развёрнутый анализ без лишних запросов.")
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
                    Text("Месяц")
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
                    runBudgetLLMRequest(force: true)
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

    private func monthTitle(_ m: MonthlyStats) -> String {
        let names = ["", "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
        let name = m.month >= 1 && m.month <= 12 ? names[m.month] : "\(m.month)"
        return "Месяц: \(name) \(m.year)"
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
                .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    private func runBudgetLLMRequest(force: Bool = false) {
        guard let today = todaySummary, let month = monthStats else { return }
        if isAILoading { return }
        if !force, hasAttemptedLLM { return }
        isAILoading = true
        if force { llmError = nil }
        let prev = previousMonthStats

        // На запрос ИИ подгружаем ещё 6 месяцев агрегатов (safe, без транзакций).
        fetchRecentMonthlyStats(monthsBack: 6, userId: selectedUserId) { recent in
            let deltaExpensePct: Double
            if let previous = prev, abs(previous.total_expense) > 0 {
                deltaExpensePct = (abs(month.total_expense) - abs(previous.total_expense)) / abs(previous.total_expense) * 100
            } else {
                deltaExpensePct = 0
            }

            let series = buildBudgetSeries(from: recent)
            let breakdowns = buildBudgetBreakdowns(currentMonth: month)
            let comparisons = buildBudgetComparisons(current: month, previous: prev)

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
                series: series.isEmpty ? nil : series,
                breakdowns: breakdowns.isEmpty ? nil : breakdowns,
                comparisons: comparisons.isEmpty ? nil : comparisons,
                notes: "safe_payload_only"
            )
            authManager.getInsight(kind: "budget", payload: payload, provider: nil) { result in
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
    }

    private func fetchRecentMonthlyStats(monthsBack: Int, userId: Int?, completion: @escaping ([MonthlyStats]) -> Void) {
        let cal = Calendar.current
        var d = Date()
        var targets: [(y: Int, m: Int)] = []
        for _ in 0..<max(1, monthsBack) {
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            targets.append((y, m))
            d = cal.date(byAdding: .month, value: -1, to: d) ?? d
        }
        let g = DispatchGroup()
        var out: [MonthlyStats] = []
        for t in targets {
            g.enter()
            authManager.getMonthlyStats(year: t.y, month: t.m, userId: userId) { r in
                defer { g.leave() }
                if case .success(let s) = r { out.append(s) }
            }
        }
        g.notify(queue: .main) {
            // Сортируем по времени по возрастанию (для графика/серий)
            let sorted = out.sorted { a, b in
                if a.year != b.year { return a.year < b.year }
                return a.month < b.month
            }
            completion(sorted)
        }
    }

    private func buildBudgetSeries(from months: [MonthlyStats]) -> [InsightSeries] {
        guard !months.isEmpty else { return [] }
        let pointsBalance = months.map { m in
            InsightPoint(t: String(format: "%04d-%02d", m.year, m.month), v: m.balance)
        }
        let pointsExpense = months.map { m in
            InsightPoint(t: String(format: "%04d-%02d", m.year, m.month), v: abs(m.total_expense))
        }
        return [
            InsightSeries(name: "Сальдо по месяцам", points: pointsBalance, unit: "RUB"),
            InsightSeries(name: "Расходы по месяцам", points: pointsExpense, unit: "RUB"),
        ]
    }

    private func buildBudgetBreakdowns(currentMonth: MonthlyStats) -> [InsightBreakdown] {
        let rows = currentMonth.details
            .filter { $0.type == "expense" }
            .sorted { abs($0.amount) > abs($1.amount) }
        let top = rows.prefix(8)
        let total = max(1.0, rows.map { abs($0.amount) }.reduce(0, +))
        let items = top.map { row in
            let v = abs(row.amount)
            return InsightBreakdownItem(name: row.category_name, value: v, share: v / total)
        }
        if items.isEmpty { return [] }
        return [
            InsightBreakdown(name: "Топ расходов по категориям (месяц)", items: items, unit: "RUB")
        ]
    }

    private func buildBudgetComparisons(current: MonthlyStats, previous: MonthlyStats?) -> [InsightComparison] {
        guard let previous else { return [] }
        let curExp = abs(current.total_expense)
        let prevExp = abs(previous.total_expense)
        let expDelta = curExp - prevExp
        let expDeltaPct = prevExp > 0 ? (expDelta / prevExp) * 100 : nil

        return [
            InsightComparison(
                name: "Расходы: текущий vs прошлый",
                a_label: "текущий",
                a_value: curExp,
                b_label: "прошлый",
                b_value: prevExp,
                delta: expDelta,
                delta_pct: expDeltaPct,
                unit: "RUB"
            ),
            InsightComparison(
                name: "Сальдо: текущий vs прошлый",
                a_label: "текущий",
                a_value: current.balance,
                b_label: "прошлый",
                b_value: previous.balance,
                delta: current.balance - previous.balance,
                delta_pct: nil,
                unit: "RUB"
            ),
        ]
    }
}

#Preview {
    NavigationStack {
        BudgetAnalyticsHubView(initialUserId: nil)
            .environmentObject(AuthManager())
    }
}
