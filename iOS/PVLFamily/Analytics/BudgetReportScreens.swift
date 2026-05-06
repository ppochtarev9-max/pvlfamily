import SwiftUI
import Charts

// MARK: - Helpers (period navigation)

private enum BudgetPeriodUI {
    static func monthStart(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    static func shiftMonth(_ date: Date, by delta: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: delta, to: date) ?? date
    }

    static func yearMonth(_ date: Date) -> (year: Int, month: Int) {
        let cal = Calendar.current
        return (cal.component(.year, from: date), cal.component(.month, from: date))
    }

    static func monthLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%02d.%d", m, y)
    }
}

// MARK: - Топ категорий расхода (текущий месяц)

struct BudgetTopExpenseCategoriesView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?
    let initialMonth: Date?

    @State private var stats: MonthlyStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

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
                        periodHeader(title: "Месяц: \(BudgetPeriodUI.monthLabel(anchorMonth))")
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

    private func periodHeader(title: String) -> some View {
        HStack(spacing: 10) {
            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    private func load() {
        isLoading = true
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
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
    let initialMonth: Date?

    @State private var cur: MonthlyStats?
    @State private var prev: MonthlyStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let c = cur, let p = prev {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        periodHeader
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

    private var periodHeader: some View {
        HStack(spacing: 10) {
            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text("Месяц: \(BudgetPeriodUI.monthLabel(anchorMonth)) vs прошлый")
                .font(.subheadline.weight(.semibold))
            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .foregroundStyle(.secondary)
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
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
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
    let initialMonth: Date?

    @State private var months: [MonthlyStats] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date
    @State private var windowMonths: Int = 3

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(.borderless)
                                Text("Окно: \(windowMonths) мес · до \(BudgetPeriodUI.monthLabel(anchorMonth))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.borderless)
                                Spacer()
                            }
                            Picker("Окно", selection: $windowMonths) {
                                Text("3").tag(3)
                                Text("6").tag(6)
                                Text("12").tag(12)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: windowMonths) { _, _ in load() }
                        }
                    } header: {
                        Text("Период")
                    }

                    Section("Средние за выбранное окно") {
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
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
        var targets: [(Int, Int)] = []
        for i in 0..<max(1, windowMonths) {
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
    let initialMonth: Date?

    @State private var rows: [(String, Double)] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date
    @State private var windowMonths: Int = 6

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Text("Окно: \(windowMonths) мес · до \(BudgetPeriodUI.monthLabel(anchorMonth))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                Picker("Окно", selection: $windowMonths) {
                    Text("6").tag(6)
                    Text("12").tag(12)
                }
                .pickerStyle(.segmented)
                .onChange(of: windowMonths) { _, _ in load() }
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
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
        var targets: [(Int, Int, String)] = []
        for i in 0..<max(1, windowMonths) {
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

// MARK: - 6 месяцев: доходы / расходы / сальдо (линии)

struct BudgetSixMonthIncomeExpenseTrendView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?
    let initialMonth: Date?

    @State private var months: [MonthlyStats] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date
    @State private var windowMonths: Int = 6

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.borderless)
                            Text("Окно: \(windowMonths) мес · до \(BudgetPeriodUI.monthLabel(anchorMonth))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.borderless)
                            Spacer()
                        }
                        Picker("Окно", selection: $windowMonths) {
                            Text("6").tag(6)
                            Text("12").tag(12)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: windowMonths) { _, _ in load() }
                        if #available(iOS 17.0, *) {
                            Chart(seriesRows(), id: \.id) { row in
                                LineMark(
                                    x: .value("Месяц", row.monthLabel),
                                    y: .value("Сумма", row.value)
                                )
                                .foregroundStyle(by: .value("Серия", row.series))
                                PointMark(
                                    x: .value("Месяц", row.monthLabel),
                                    y: .value("Сумма", row.value)
                                )
                                .foregroundStyle(by: .value("Серия", row.series))
                            }
                            .chartForegroundStyleScale([
                                "Доходы": FamilyAppStyle.incomeGreen,
                                "Расходы": FamilyAppStyle.expenseCoral,
                                "Сальдо": FamilyAppStyle.accent
                            ])
                            .frame(height: 260)
                        }
                        VStack(spacing: 8) {
                            ForEach(months, id: \.month) { m in
                                HStack {
                                    Text(String(format: "%02d.%d", m.month, m.year))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Доход \(AnalyticsFormatters.moneyRU(m.total_income))")
                                        .font(.caption)
                                        .foregroundStyle(FamilyAppStyle.incomeGreen)
                                    Text("Расход \(AnalyticsFormatters.moneyRU(abs(m.total_expense)))")
                                        .font(.caption)
                                        .foregroundStyle(FamilyAppStyle.expenseCoral)
                                }
                            }
                        }
                        Text("Три линии: доходы, расходы и сальдо. Это лучше, чем 3 отдельных графика — видно динамику и разрыв.")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("6 месяцев: тренды")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct Row: Identifiable {
        let id: String
        let monthLabel: String
        let series: String
        let value: Double
    }

    private func seriesRows() -> [Row] {
        months.flatMap { m in
            let label = String(format: "%02d.%d", m.month, m.year)
            return [
                Row(id: "\(label)-inc", monthLabel: label, series: "Доходы", value: m.total_income),
                Row(id: "\(label)-exp", monthLabel: label, series: "Расходы", value: abs(m.total_expense)),
                Row(id: "\(label)-bal", monthLabel: label, series: "Сальдо", value: m.balance)
            ]
        }
    }

    private func load() {
        isLoading = true
        error = nil
        let cal = Calendar.current
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
        var targets: [(Int, Int)] = []
        for i in 0..<max(1, windowMonths) {
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
            months = collected.sorted { a, b in
                if a.year != b.year { return a.year < b.year }
                return a.month < b.month
            }
            if months.isEmpty { error = "Нет данных" }
        }
    }
}

// MARK: - Структура расходов (donut)

struct BudgetExpenseStructureDonutView: View {
    @EnvironmentObject var authManager: AuthManager
    var userId: Int?
    let initialMonth: Date?

    @State private var stats: MonthlyStats?
    @State private var isLoading = true
    @State private var error: String?
    @State private var anchorMonth: Date

    init(userId: Int?, initialMonth: Date? = nil) {
        self.userId = userId
        self.initialMonth = initialMonth
        _anchorMonth = State(initialValue: BudgetPeriodUI.monthStart(initialMonth ?? Date()))
    }

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let rows = Self.expenseSlices(from: s)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: -1); load() } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.borderless)
                            Text("Месяц: \(BudgetPeriodUI.monthLabel(anchorMonth))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Button { anchorMonth = BudgetPeriodUI.shiftMonth(anchorMonth, by: 1); load() } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.borderless)
                            Spacer()
                        }
                        if #available(iOS 17.0, *) {
                            Chart(rows, id: \.name) { item in
                                SectorMark(
                                    angle: .value("Доля", item.value),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.0
                                )
                                .foregroundStyle(by: .value("Категория", item.name))
                            }
                            .frame(height: 260)
                        }
                        VStack(spacing: 8) {
                            ForEach(rows, id: \.name) { item in
                                HStack {
                                    Text(item.name).lineLimit(1)
                                    Spacer()
                                    Text(AnalyticsFormatters.moneyRU(item.value))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("Сектора показывают структуру расходов за месяц: топ-категории + «прочее».")
                            .font(.caption2)
                            .foregroundStyle(FamilyAppStyle.captionMuted)
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Структура расходов")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private struct Slice {
        let name: String
        let value: Double
    }

    private static func expenseSlices(from s: MonthlyStats) -> [Slice] {
        let exp = s.details
            .filter { $0.type == "expense" }
            .map { (name: $0.category_name, value: abs($0.amount)) }
            .sorted { $0.value > $1.value }
        let top = exp.prefix(6)
        let topSum = top.map(\.value).reduce(0, +)
        let total = exp.map(\.value).reduce(0, +)
        var out = top.map { Slice(name: $0.name, value: $0.value) }
        let other = max(0, total - topSum)
        if other > 0 { out.append(Slice(name: "Прочее", value: other)) }
        return out
    }

    private func load() {
        isLoading = true
        error = nil
        let (y, m) = BudgetPeriodUI.yearMonth(anchorMonth)
        authManager.getMonthlyStats(year: y, month: m, userId: userId) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
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
