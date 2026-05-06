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

    @State private var anchorMonth = Date()
    @State private var todaySummary: DashboardSummary?
    @State private var monthStats: MonthlyStats?
    @State private var previousMonthStats: MonthlyStats?
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
                            BudgetTopExpenseCategoriesView(userId: selectedUserId, initialMonth: anchorMonth)
                        } label: {
                            Label("Топ категорий расхода (месяц)", systemImage: "list.number")
                        }
                        NavigationLink {
                            BudgetExpenseStructureDonutView(userId: selectedUserId, initialMonth: anchorMonth)
                        } label: {
                            Label("Структура расходов (месяц)", systemImage: "chart.pie")
                        }
                        NavigationLink {
                            BudgetMonthOverMonthView(userId: selectedUserId, initialMonth: anchorMonth)
                        } label: {
                            Label("Сравнение с прошлым месяцем", systemImage: "arrow.left.arrow.right")
                        }
                        NavigationLink {
                            BudgetThreeMonthAverageView(userId: selectedUserId, initialMonth: anchorMonth)
                        } label: {
                            Label("Средние за 3 месяца", systemImage: "function")
                        }
                        NavigationLink {
                            BudgetSixMonthStripView(userId: selectedUserId, initialMonth: anchorMonth)
                        } label: {
                            Label("6 месяцев: сальдо (тренд-таблица)", systemImage: "tablecells")
                        }
                        NavigationLink {
                            BudgetSixMonthIncomeExpenseTrendView(userId: selectedUserId, initialMonth: anchorMonth)
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
                                selectedSubcategoryId: $selectedSubcategoryId,
                                initialMonth: anchorMonth
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
        .safeAreaInset(edge: .top, spacing: 0) {
            monthSwitcher
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(FamilyAppStyle.screenBackground)
        }
        .navigationTitle("Аналитика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BudgetAIChatView(selectedUserId: selectedUserId, anchorMonth: anchorMonth)
                        .environmentObject(authManager)
                } label: {
                    Label("ИИ", systemImage: "sparkles")
                }
                .disabled(isLoading || loadError != nil)
            }
        }
        .onAppear {
            if selectedUserId == nil { selectedUserId = initialUserId }
            anchorMonth = monthStart(Date())
            loadSnapshot()
        }
    }

    private var snapshotBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let m = monthStats {
                snapshotCard(
                    title: monthTitle(m),
                    primary: "Расходы \(formatMoney(abs(m.total_expense)))",
                    secondary: "Доходы \(formatMoney(m.total_income))",
                    caption: BudgetInsightBuilder.monthLine(current: m, previous: previousMonthStats)
                )
            }
            Text("ИИ: нажмите «ИИ» вверху, чтобы открыть чат и задать вопрос по бюджету.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 10) {
            Button {
                shiftAnchorMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(monthLabel(anchorMonth))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                shiftAnchorMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    private func monthStart(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func monthLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let names = ["", "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
        let name = m >= 1 && m <= 12 ? names[m] : "\(m)"
        return "\(name) \(y)"
    }

    private func shiftAnchorMonth(by delta: Int) {
        let cal = Calendar.current
        let next = cal.date(byAdding: .month, value: delta, to: anchorMonth) ?? anchorMonth
        anchorMonth = monthStart(next)

        loadSnapshot()
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

        let y = cal.component(.year, from: anchorMonth)
        let m = cal.component(.month, from: anchorMonth)
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
            if curMonth == nil {
                loadError = blockError ?? "Не удалось получить сводку"
                return
            }
            todaySummary = today
            monthStats = curMonth
            previousMonthStats = prevMonth
        }
    }


}

#Preview {
    NavigationStack {
        BudgetAnalyticsHubView(initialUserId: nil)
            .environmentObject(AuthManager())
    }
}
