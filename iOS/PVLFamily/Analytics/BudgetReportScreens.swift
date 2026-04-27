import SwiftUI
import Charts

// MARK: - Топ категорий расхода (текущий месяц)

struct BudgetTopExpenseCategoriesView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?

    @State private var stats: MonthlyStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let rows = s.details
                    .filter { $0.type == "expense" }
                    .sorted { abs($0.amount) > abs($1.amount) }
                    .prefix(8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if #available(iOS 17.0, *) {
                            Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                                BarMark(
                                    x: .value("Сумма", abs(row.amount)),
                                    y: .value("Категория", row.category_name)
                                )
                                .foregroundStyle(FamilyAppStyle.expenseCoral.gradient)
                            }
                            .frame(height: 280)
                        }
                        VStack(spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack {
                                    Text(row.category_name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(AnalyticsFormatters.moneyRU(abs(row.amount)))
                                        .foregroundStyle(FamilyAppStyle.expenseCoral)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Топ расходов")
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        let cal = Calendar.current
        let d = Date()
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        authManager.getMonthlyStats(year: y, month: m, userId: userId) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Сравнение с прошлым месяцем (таблица)

struct BudgetMonthOverMonthView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?

    @State private var cur: MonthlyStats?
    @State private var prev: MonthlyStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let c = cur, let p = prev {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if #available(iOS 17.0, *) {
                            Chart(comparisonRows(c: c, p: p), id: \.id) { row in
                                BarMark(
                                    x: .value("Метка", row.label),
                                    y: .value("Сумма", row.value)
                                )
                                .foregroundStyle(by: .value("Период", row.period))
                            }
                            .chartForegroundStyleScale([
                                "Текущий": FamilyAppStyle.accent,
                                "Прошлый": FamilyAppStyle.captionMuted
                            ])
                            .frame(height: 250)
                        }
                        VStack(spacing: 8) {
                            compareRow("Доходы · текущий", c.total_income)
                            compareRow("Доходы · прошлый", p.total_income)
                            compareRow("Расходы · текущий", abs(c.total_expense))
                            compareRow("Расходы · прошлый", abs(p.total_expense))
                            compareRow("Сальдо · текущий", c.balance)
                            compareRow("Сальдо · прошлый", p.balance)
                        }
                        if abs(c.total_expense) > 0, abs(p.total_expense) > 0 {
                            let ch = (abs(c.total_expense) - abs(p.total_expense)) / abs(p.total_expense) * 100
                            Text("Расходы относительно прошлого месяца: \(String(format: "%.0f", ch))%")
                                .font(.footnote)
                                .foregroundStyle(FamilyAppStyle.captionMuted)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Месяц к месяцу")
        .onAppear(perform: load)
    }

    private func compareRow(_ title: String, _ v: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(AnalyticsFormatters.moneyRU(v))
        }
    }

    private struct ComparisonRow: Identifiable {
        let id: String
        let label: String
        let period: String
        let value: Double
    }

    private func comparisonRows(c: MonthlyStats, p: MonthlyStats) -> [ComparisonRow] {
        [
            ComparisonRow(id: "income-current", label: "Доходы", period: "Текущий", value: c.total_income),
            ComparisonRow(id: "income-prev", label: "Доходы", period: "Прошлый", value: p.total_income),
            ComparisonRow(id: "expense-current", label: "Расходы", period: "Текущий", value: abs(c.total_expense)),
            ComparisonRow(id: "expense-prev", label: "Расходы", period: "Прошлый", value: abs(p.total_expense)),
            ComparisonRow(id: "balance-current", label: "Сальдо", period: "Текущий", value: c.balance),
            ComparisonRow(id: "balance-prev", label: "Сальдо", period: "Прошлый", value: p.balance)
        ]
    }

    private func load() {
        isLoading = true
        let cal = Calendar.current
        let d = Date()
        var y = cal.component(.year, from: d)
        var m = cal.component(.month, from: d)
        var py = y, pm = m - 1
        if pm < 1 { pm = 12; py -= 1 }
        let g = DispatchGroup()
        g.enter()
        authManager.getMonthlyStats(year: y, month: m, userId: userId) { r in
            defer { g.leave() }
            if case .success(let s) = r { cur = s }
        }
        g.enter()
        authManager.getMonthlyStats(year: py, month: pm, userId: userId) { r in
            defer { g.leave() }
            if case .success(let s) = r { prev = s }
        }
        g.notify(queue: .main) {
            isLoading = false
            if cur == nil { error = "Нет данных за текущий месяц" }
            if prev == nil, error == nil { error = "Нет данных за прошлый месяц" }
        }
    }
}

// MARK: - Средние за 3 месяца

struct BudgetThreeMonthAverageView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?

    @State private var months: [MonthlyStats] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                List {
                    Section("Средние за 3 полных календарных месяца") {
                        if !months.isEmpty {
                            let c = max(1, months.count)
                            let inc = months.map(\.total_income).reduce(0, +) / Double(c)
                            let exp = months.map { abs($0.total_expense) }.reduce(0, +) / Double(c)
                            HStack { Text("Ср. доход / мес"); Spacer(); Text(AnalyticsFormatters.moneyRU(inc)) }
                            HStack { Text("Ср. расход / мес"); Spacer(); Text(AnalyticsFormatters.moneyRU(exp)) }
                            if months.count < 3 {
                                Text("Загружено \(months.count) из 3 — проверьте, что в архиве есть ранние месяцы.")
                                    .font(.caption2)
                                    .foregroundStyle(FamilyAppStyle.captionMuted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Средние 3 мес")
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        let cal = Calendar.current
        var d = Date()
        var y = cal.component(.year, from: d)
        var m = cal.component(.month, from: d)
        // берём 3 прошедших «полных» месяца: сдвиг от текущего
        var targets: [(Int, Int)] = []
        for i in 0..<3 {
            var mm = m - i
            var yy = y
            while mm < 1 { mm += 12; yy -= 1 }
            targets.append((yy, mm))
        }
        let g = DispatchGroup()
        var collected: [MonthlyStats] = []
        for t in targets {
            g.enter()
            authManager.getMonthlyStats(year: t.0, month: t.1, userId: userId) { r in
                defer { g.leave() }
                if case .success(let s) = r { collected.append(s) }
            }
        }
        g.notify(queue: .main) {
            isLoading = false
            months = collected
        }
    }
}

// MARK: - Тренд по месяцам (последние 6)

struct BudgetSixMonthStripView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?

    @State private var rows: [(String, Double)] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if #available(iOS 17.0, *) {
                    Chart(rows, id: \.0) { row in
                        LineMark(
                            x: .value("Месяц", row.0),
                            y: .value("Сальдо", row.1)
                        )
                        .foregroundStyle(FamilyAppStyle.accent)
                        PointMark(
                            x: .value("Месяц", row.0),
                            y: .value("Сальдо", row.1)
                        )
                        .foregroundStyle(FamilyAppStyle.accent)
                    }
                    .frame(height: 220)
                }
                VStack(spacing: 8) {
                    if rows.isEmpty && !isLoading { Text("Нет данных") }
                    ForEach(rows, id: \.0) { r in
                        HStack {
                            Text(r.0)
                            Spacer()
                            Text(AnalyticsFormatters.moneyRU(r.1))
                                .font(.caption)
                        }
                    }
                }
                Text("Линия показывает тренд сальдо по месяцам; для прогноза добавим агрегат API.")
                    .font(.caption2)
                    .foregroundStyle(FamilyAppStyle.captionMuted)
            }
            .padding()
        }
        .navigationTitle("6 месяцев: сальдо")
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        let cal = Calendar.current
        var d = Date()
        var y = cal.component(.year, from: d)
        var m = cal.component(.month, from: d)
        var targets: [(Int, Int, String)] = []
        for i in 0..<6 {
            var mm = m - i
            var yy = y
            while mm < 1 { mm += 12; yy -= 1 }
            let label = String(format: "%02d.%d", mm, yy)
            targets.append((yy, mm, label))
        }
        let g = DispatchGroup()
        var out: [(String, Double)] = []
        for t in targets {
            g.enter()
            authManager.getMonthlyStats(year: t.0, month: t.1, userId: userId) { r in
                defer { g.leave() }
                if case .success(let s) = r { out.append((t.2, s.balance)) }
            }
        }
        g.notify(queue: .main) {
            isLoading = false
            rows = out.reversed()
        }
    }
}

// MARK: - Заглушки под будущие «выбросы по суммам» и кастомный период

struct BudgetAnomaliesScaffoldView: View {
    var body: some View {
        ContentUnavailableView(
            "Скоро: выбросы",
            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
            description: Text("Список крупных операций за период потребует отдельного агрегата на API с фильтром и перцентилями — подключим в следующей итерации DATA-04.")
        )
        .navigationTitle("Крупные операции")
    }
}

struct BudgetCustomPeriodScaffoldView: View {
    var body: some View {
        ContentUnavailableView(
            "Произвольный период",
            systemImage: "calendar.badge.clock",
            description: Text("Сравнение двух кастомных окон в одном отчёте — запланировано; пока используйте фильтры на экране бюджета и экспорт в Excel.")
        )
        .navigationTitle("Свой период")
    }
}
