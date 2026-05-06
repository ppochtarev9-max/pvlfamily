import SwiftUI

// MARK: - 🟢 ГЛАВНЫЙ ВИД: BUDGET VIEW
struct BudgetView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var allTransactions: [Transaction] = []
    @State private var categoryGroups: [CategoryGroup] = [] // НОВОЕ: Группы вместо плоского списка
    
    // Состояния фильтров
    @State private var showingFilterSheet = false
    @State private var selectedDateFilter: DateFilter = .all
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    
    @State private var selectedGroupId: Int? = nil       // НОВОЕ
    @State private var selectedSubcategoryId: Int? = nil // НОВОЕ
    
    // Для баланса
    @State private var summary: DashboardSummary?
    @State private var isLoadingBalance = false

    /// Кэш групп дней — не пересчитывать O(n) на каждый кадр SwiftUI (см. `groupedTransactions` раньше).
    @State private var transactionDaySections: [TransactionDaySection] = []
    @State private var didRunInitialBudgetLoad = false
    
    /// Пагинация ленты операций (keyset, без смещения offset).
    @State private var hasMoreTransactions = false
    @State private var isLoadingMoreTransactions = false
    @State private var nextTransactionCursor: (dateISO: String, id: Int)? = nil
    
    // Фильтр по пользователю
    @State private var selectedUserId: Int? = nil
    
    // Навигация
    @State private var navigateToAnalytics = false
    @State private var balanceDate = Date()
    @State private var showBalanceCalendar = false
    
    // Ошибки
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isSaving = false

    // Скролл к «Сегодня» в списке операций
    @State private var didAutoScrollToToday = false
    @State private var visibleSectionId: String? = nil

    // Вычисляемые свойства для фильтров
    var availableGroups: [CategoryGroup] {
        categoryGroups.filter { !$0.is_hidden }.sorted { $0.name < $1.name }
    }
    
    var availableSubcategories: [SubCategory] {
        guard let groupId = selectedGroupId,
              let group = categoryGroups.first(where: { $0.id == groupId }) else { return [] }
        return group.subcategories.filter { !$0.is_hidden }.sorted { $0.name < $1.name }
    }
    
    // Плоский список всех подкатегорий для быстрого поиска (если нужно)
    var allAvailableSubcategories: [SubCategory] {
        categoryGroups.flatMap { $0.subcategories }.filter { !$0.is_hidden }
    }

    /// Снимок в памяти, без пересчёта при каждом `body` (нужен для 10⁴–10⁵ операций).
    private func computeFilteredTransactions() -> [Transaction] {
        var result = allTransactions
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedDateFilter {
        case .all: break
        case .today: result = result.filter { isSameDay(dateString: $0.date, to: now) }
        case .yesterday:
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                result = result.filter { isSameDay(dateString: $0.date, to: yesterday) }
            }
        case .week:
            if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
                result = result.filter {
                    guard let d = PVLDateParsing.parse($0.date) else { return false }
                    return d >= startOfWeek && d <= now
                }
            }
        case .month:
            if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) {
                result = result.filter {
                    guard let d = PVLDateParsing.parse($0.date) else { return false }
                    return d >= startOfMonth && d <= now
                }
            }
        case .custom:
            result = result.filter {
                guard let d = PVLDateParsing.parse($0.date) else { return false }
                return d >= customStartDate && d <= customEndDate
            }
        }
        
        if let subId = selectedSubcategoryId {
            result = result.filter { $0.category_id == subId }
        } else if let groupId = selectedGroupId {
            let subIds = categoryGroups
                .first(where: { $0.id == groupId })?
                .subcategories.map { $0.id } ?? []
            result = result.filter { subIds.contains($0.category_id) }
        }
        
        return result
    }

    private func refreshTransactionDaySections() {
        let filtered = computeFilteredTransactions()
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { tx in
            PVLDateParsing.parse(tx.date).map { cal.startOfDay(for: $0) } ?? .distantPast
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        let dayTitleFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "dd.MM"
            return f
        }()
        transactionDaySections = sortedKeys.map { day in
            let items = (grouped[day] ?? []).sorted { $0.date > $1.date }
            let total = items.reduce(0.0) { $0 + $1.amount }
            let title: String
            if cal.isDateInToday(day) { title = "Сегодня" }
            else if cal.isDateInYesterday(day) { title = "Вчера" }
            else { title = dayTitleFormatter.string(from: day) }
            let prefix = total >= 0 ? "+₽ " : "−₽ "
            let summary = prefix + String(format: "%.0f", abs(total))
            return TransactionDaySection(
                id: "\(day.timeIntervalSince1970)",
                day: day,
                title: title,
                summary: summary,
                summaryHasIncome: total >= 0,
                items: items
            )
        }
    }

    private var todaySectionId: String? {
        transactionDaySections.first(where: { Calendar.current.isDateInToday($0.day) })?.id
    }
    
    enum DateFilter: String, CaseIterable {
        case all = "Все даты"
        case today = "Сегодня"
        case yesterday = "Вчера"
        case week = "Эта неделя"
        case month = "Этот месяц"
        case custom = "Выбрать период..."
    }
    
    // --- МОДЕЛИ ДАННЫХ (Обновленные) ---
    fileprivate struct TransactionListPage: Codable {
        let items: [Transaction]
        let has_more: Bool
        let total: Int
    }
    
    struct Transaction: Identifiable, Codable {
        let id: Int
        let amount: Double
        let transaction_type: String
        let category_id: Int
        let description: String?
        let date: String
        let creator_name: String?
        let full_category_path: String? // "Группа / Подкатегория"
        let balance: Double?
    }

    fileprivate struct TransactionDaySection: Identifiable {
        let id: String
        let day: Date
        let title: String
        let summary: String
        let summaryHasIncome: Bool
        let items: [Transaction]
    }
    
    // --- МОДЕЛИ ДАННЫХ (Обновленные с Hashable и Equatable) ---
    
    struct SubCategory: Identifiable, Codable, Hashable, Equatable {
        let id: Int
        var name: String          // Изменил на var для возможности редактирования
        let group_id: Int
        var is_hidden: Bool       // Изменил на var
        let group_name: String?
        
        // Реализация Equatable для структур с var
        static func == (lhs: SubCategory, rhs: SubCategory) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    struct CategoryGroup: Identifiable, Codable, Hashable, Equatable {
        let id: Int
        var name: String          // Изменил на var
        let type: String
        var is_hidden: Bool       // Изменил на var
        var subcategories: [SubCategory] // Изменил на var
        
        // Реализация Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        // Реализация Equatable
        static func == (lhs: CategoryGroup, rhs: CategoryGroup) -> Bool {
            return lhs.id == rhs.id
        }
    }
//    struct DashboardSummary: Codable {
//        let balance: Double
//        let total_income: Double
//        let total_expense: Double
//    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // БЛОК 1: баланс + кнопка (без фикс. высоты — иначе под ScrollView с «хвостом» остаётся пустой зазор)
                VStack(spacing: 8) {
                    Group {
                        if let s = summary {
                            VStack(alignment: .center, spacing: 6) {
                                Text(formatBalancePixso(s.balance))
                                    .font(.system(size: 34, weight: .bold))
                                    .kerning(-0.5)
                                    .foregroundColor(s.balance >= 0 ? FamilyAppStyle.pixsoInk : .red)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        } else if isLoadingBalance {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        } else {
                            Text("Нет данных")
                                .font(.subheadline)
                                .foregroundColor(FamilyAppStyle.captionMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .pvlPixsoHeroPanel()
                    .padding(.horizontal)
                    
                    Button(action: { navigateToAnalytics = true }) {
                        Text("Аналитика")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FamilyAppStyle.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal)
                }
                
                Text("Операции")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                
                // БЛОК 2: СПИСОК
                Group {
                    if transactionDaySections.isEmpty {
                        ContentUnavailableView("Нет записей", systemImage: "list.bullet.rectangle", description: Text("Измените фильтры или добавьте операцию"))
                    } else {
                        ScrollViewReader { proxy in
                            List {
                                ForEach(transactionDaySections) { section in
                                    let n = section.items.count
                                    Section {
                                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, t in
                                            TransactionCard(t: t, isLastInGroup: index == n - 1)
                                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                                .listRowSeparator(.hidden, edges: .all)
                                                .listRowBackground(
                                                    PVLGroupedRowBackground(
                                                        isFirst: index == 0,
                                                        isLast: index == n - 1,
                                                        isSingle: n == 1
                                                    )
                                                )
                                                .swipeActions {
                                                    Button(role: .destructive) { deleteTransaction(id: t.id) } label: { Label("Удалить", systemImage: "trash") }
                                                    Button { editTransaction(t) } label: { Label("Изменить", systemImage: "pencil") }.tint(FamilyAppStyle.accent)
                                                }
                                        }
                                    } header: {
                                        HStack {
                                            Text(section.title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(FamilyAppStyle.sectionHeaderForeground)
                                            Spacer()
                                            Text(section.summary)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(section.summaryHasIncome ? FamilyAppStyle.incomeGreen : FamilyAppStyle.expenseCoral)
                                        }
                                        .textCase(nil)
                                        .onAppear { visibleSectionId = section.id }
                                    }
                                    .id(section.id)
                                }
                                if hasMoreTransactions {
                                    Section {
                                        HStack {
                                            Spacer()
                                            if isLoadingMoreTransactions {
                                                ProgressView()
                                            } else {
                                                Color.clear
                                                    .frame(height: 1)
                                                    .onAppear { loadMoreTransactionsIfNeeded() }
                                            }
                                            Spacer()
                                        }
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .listRowSpacing(0)
                            .listSectionSpacing(8)
                            .scrollContentBackground(.hidden)
                            .onAppear {
                                guard !didAutoScrollToToday, let todayId = todaySectionId else { return }
                                didAutoScrollToToday = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation(.easeInOut) { proxy.scrollTo(todayId, anchor: .top) }
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if let todayId = todaySectionId,
                                   let visible = visibleSectionId,
                                   visible != todayId {
                                    Button {
                                        withAnimation(.easeInOut) { proxy.scrollTo(todayId, anchor: .top) }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.down.to.line.compact")
                                            Text("К сегодня")
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(FamilyAppStyle.listCardFill)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(FamilyAppStyle.cardStroke, lineWidth: 1))
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 14)
                                }
                            }
                        }
                    }
                }
            }
            .background(FamilyAppStyle.screenBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToAnalytics) {
                BudgetAnalyticsHubView(initialUserId: selectedUserId)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("Бюджет на ")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        Button(action: { showBalanceCalendar = true }) {
                            HStack(spacing: 2) {
                                Text(formatDateShort(balanceDate))
                                    .fontWeight(.medium)
                                Image(systemName: "calendar")
                                    .font(.caption)
                            }
                            .foregroundColor(FamilyAppStyle.accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 15) {
                        Button(action: { showingFilterSheet = true }) {
                            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .foregroundColor(hasActiveFilters ? FamilyAppStyle.accent : FamilyAppStyle.captionMuted)
                        }
                        Button(action: { startNewTransaction() }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showBalanceCalendar) {
                VStack(spacing: 20) {
                    DatePicker("", selection: $balanceDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: balanceDate) { _, _ in
                            showBalanceCalendar = false
                            loadBalance()
                        }
                    Button("Закрыть") { showBalanceCalendar = false }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 20)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheet(
                    selectedDateFilter: $selectedDateFilter,
                    startDate: $customStartDate,
                    endDate: $customEndDate,
                    selectedGroupId: $selectedGroupId,       // Обновлено
                    selectedSubcategoryId: $selectedSubcategoryId, // Обновлено
                    selectedUserId: $selectedUserId,
                    users: authManager.users,
                    groups: availableGroups,                 // Обновлено
                    subcategories: availableSubcategories,   // Обновлено
                    isPresented: $showingFilterSheet,
                    onUpdate: {
                        loadTransactions(reset: true)
                        loadBalance()
                    }
                )
            }
            // Создание новой операции
            .sheet(isPresented: $showingAddSheet) {
                TransactionFormView(
                    isPresented: $showingAddSheet,
                    categoryGroups: categoryGroups,
                    transactionToEdit: nil,
                    onSave: { id, amount, type, catId, desc, date in
                        let finalCategoryId = catId ?? 17
                        saveTransaction(id: id, amount: amount, type: type, categoryId: finalCategoryId, description: desc, date: date)
                    },
                    onDelete: deleteTransaction
                )
            }
            // Редактирование существующей операции (устойчиво: без бага "открылось как новая")
            .sheet(item: $editingTransaction) { tx in
                TransactionFormView(
                    isPresented: Binding(
                        get: { true },
                        set: { newValue in
                            if !newValue { editingTransaction = nil }
                        }
                    ),
                    categoryGroups: categoryGroups,
                    transactionToEdit: tx,
                    onSave: { id, amount, type, catId, desc, date in
                        let finalCategoryId = catId ?? 17
                        saveTransaction(id: id, amount: amount, type: type, categoryId: finalCategoryId, description: desc, date: date)
                    },
                    onDelete: deleteTransaction
                )
                .id(tx.id)
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .onAppear {
                if !didRunInitialBudgetLoad {
                    didRunInitialBudgetLoad = true
                    loadData()
                } else {
                    loadBalance()
                }
            }
            .onChange(of: selectedDateFilter) { _, _ in loadTransactions(reset: true) }
            .onChange(of: selectedGroupId) { _, _ in loadTransactions(reset: true) }
            .onChange(of: selectedSubcategoryId) { _, _ in loadTransactions(reset: true) }
            .onChange(of: customStartDate) { _, _ in
                if selectedDateFilter == .custom { loadTransactions(reset: true) }
            }
            .onChange(of: customEndDate) { _, _ in
                if selectedDateFilter == .custom { loadTransactions(reset: true) }
            }
            .onChange(of: categoryGroups.count) { _, _ in refreshTransactionDaySections() }
            .refreshable {
                await withCheckedContinuation { continuation in
                    loadData()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { continuation.resume() }
                }
            }
        }
    }
    
    var hasActiveFilters: Bool {
        selectedDateFilter != .all || selectedGroupId != nil || selectedUserId != nil
    }
    
    @State private var showingAddSheet = false
    @State private var editingTransaction: Transaction? = nil
    
    func colorForType(_ type: String) -> Color {
        switch type { case "income": return .green; case "expense": return .red; default: return .primary }
    }
    
    func formatAmount(_ amount: Double, type: String) -> String {
        let sign = ""
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
    }
    
    func formatDate(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: d)
        }
        if let tIndex = string.firstIndex(of: "T") {
            let datePart = String(string[..<tIndex])
            let parts = datePart.split(separator: "-")
            if parts.count == 3 { return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2)))" }
            return datePart
        }
        return string
    }
    
    func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }
    
    func isSameDay(dateString: String, to date: Date) -> Bool {
        guard let d = PVLDateParsing.parse(dateString) else { return false }
        return Calendar.current.isDate(d, inSameDayAs: date)
    }
    
    func parseDate(_ string: String) -> Date? {
        PVLDateParsing.parse(string)
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: abs(value))) ?? "0") ₽"
    }

    /// Верхняя карта: как в Pixso — «₽ 48 320» с разрядным пробелом, без копеек.
    func formatBalancePixso(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let num = formatter.string(from: NSNumber(value: abs(value.rounded()))) ?? "0"
        return "₽ \(num)"
    }
    
    func loadData() {
        print("🔄 [Budget] Загрузка данных...")
        loadBalance()
        loadCategories() // Теперь грузит группы
        loadTransactions()
    }
    
    func loadBalance() {
        isLoadingBalance = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: balanceDate)
        
        authManager.getDashboardSummary(asOfDate: dateStr, userId: selectedUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data): self.summary = data
                case .failure(let error): print("❌ Ошибка баланса: \(error)")
                }
                self.isLoadingBalance = false
            }
        }
    }
    
    private static let budgetTransactionPageLimit = 100
    
    /// Границы дат для query API (тот же смысл, что и в фильтре по памяти, но на сервере).
    /// Как `make_tx_resp` на сервере: `yyyy-MM-dd'T'HH:mm:ss` (локальные сутки, без `Z`), чтобы `fromisoformat` сравнивал с `Transaction.date` в БД.
    private func serverDateQueryBounds() -> (String, String)? {
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        func endOfDay(_ d: Date) -> Date {
            var c = cal.dateComponents([.year, .month, .day], from: d)
            c.hour = 23
            c.minute = 59
            c.second = 59
            return cal.date(from: c) ?? d
        }
        switch selectedDateFilter {
        case .all: return nil
        case .today:
            let s = cal.startOfDay(for: now)
            return (f.string(from: s), f.string(from: endOfDay(now)))
        case .yesterday:
            guard let y = cal.date(byAdding: .day, value: -1, to: now) else { return nil }
            return (f.string(from: cal.startOfDay(for: y)), f.string(from: endOfDay(y)))
        case .week:
            guard let w0 = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return nil }
            return (f.string(from: w0), f.string(from: endOfDay(now)))
        case .month:
            guard let m0 = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return nil }
            return (f.string(from: m0), f.string(from: endOfDay(now)))
        case .custom:
            let a = min(customStartDate, customEndDate)
            let b = max(customStartDate, customEndDate)
            return (f.string(from: cal.startOfDay(for: a)), f.string(from: endOfDay(b)))
        }
    }
    
    private func budgetTransactionListURL(appendPage: Bool) -> URL? {
        guard var c = URLComponents(string: "\(authManager.baseURL)/budget/transactions") else { return nil }
        var q: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(Self.budgetTransactionPageLimit)")
        ]
        if appendPage, let cur = nextTransactionCursor {
            q.append(URLQueryItem(name: "after_date", value: cur.dateISO))
            q.append(URLQueryItem(name: "after_id", value: "\(cur.id)"))
        }
        if let s = serverDateQueryBounds() {
            q.append(URLQueryItem(name: "date_from", value: s.0))
            q.append(URLQueryItem(name: "date_to", value: s.1))
        }
        if let sc = selectedSubcategoryId {
            q.append(URLQueryItem(name: "category_id", value: "\(sc)"))
        } else if let g = selectedGroupId {
            q.append(URLQueryItem(name: "group_id", value: "\(g)"))
        }
        c.queryItems = q
        return c.url
    }
    
    /// Первая страница или сброс при смене фильтра.
    func loadTransactions(reset: Bool = true) {
        if reset {
            hasMoreTransactions = false
            nextTransactionCursor = nil
            isLoadingMoreTransactions = false
            allTransactions = []
        }
        guard let url = budgetTransactionListURL(appendPage: false) else { return }
        runBudgetTransactionRequest(url: url, append: false, isLoadMore: false)
    }
    
    private func loadMoreTransactionsIfNeeded() {
        guard hasMoreTransactions, !isLoadingMoreTransactions else { return }
        guard let url = budgetTransactionListURL(appendPage: true) else { return }
        runBudgetTransactionRequest(url: url, append: true, isLoadMore: true)
    }
    
    private func runBudgetTransactionRequest(url: URL, append: Bool, isLoadMore: Bool) {
        guard let token = authManager.token else {
            errorMessage = "Требуется авторизация"
            showErrorAlert = true
            return
        }
        if isLoadMore { isLoadingMoreTransactions = true } else if !append { isLoadingMoreTransactions = false }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if isLoadMore { self.isLoadingMoreTransactions = false }
                if let error = error {
                    if !isLoadMore {
                        self.errorMessage = "Нет соединения с сервером"
                        self.showErrorAlert = true
                    }
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    if !isLoadMore {
                        self.errorMessage = "Ошибка сервера"
                        self.showErrorAlert = true
                    }
                    return
                }
                guard let data = data else { return }
                
                do {
                    let page = try JSONDecoder().decode(TransactionListPage.self, from: data)
                    if append {
                        self.allTransactions.append(contentsOf: page.items)
                    } else {
                        self.allTransactions = page.items
                    }
                    self.hasMoreTransactions = page.has_more
                    if let last = page.items.last {
                        self.nextTransactionCursor = (last.date, last.id)
                    } else {
                        self.nextTransactionCursor = nil
                    }
                    self.refreshTransactionDaySections()
                } catch {
                    if !isLoadMore {
                        self.errorMessage = "Неверный формат данных"
                        self.showErrorAlert = true
                    }
                }
            }
        }.resume()
    }
    
    func loadCategories() {
        guard let token = authManager.token else { return }
        // НОВЫЙ ЭНДПОИНТ: /budget/groups
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/groups")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Ошибка сети (категории): \(error)")
                    return
                }
                guard let data = data else {
                    print("❌ Пустой ответ категорий")
                    return
                }
                do {
                    let list = try JSONDecoder().decode([CategoryGroup].self, from: data)
                    self.categoryGroups = list
                    print("✅ Загружено групп: \(list.count)")
                } catch {
                    print("❌ Ошибка парсинга категорий: \(error)")
                    // Попробуем вывести сырой JSON для отладки если нужно
                    // print(String(data: data, encoding: .utf8) ?? "No data")
                }
            }
        }.resume()
    }
    
    func startNewTransaction() {
        editingTransaction = nil
        showingAddSheet = true
    }

    func editTransaction(_ t: Transaction) {
        editingTransaction = t
    }
    
    func saveTransaction(id: Int?, amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else {
            errorMessage = "Требуется авторизация"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        // Формируем базовый URL
        let baseURLString = "\(authManager.baseURL)/budget/transactions"
        var requestURLString = baseURLString
        
        // Если это редактирование (id есть), добавляем его к пути
        if let transactionId = id {
            requestURLString = "\(baseURLString)/\(transactionId)"
        }
        
        var req = URLRequest(url: URL(string: requestURLString)!)
        req.httpMethod = (id != nil) ? "PUT" : "POST"
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "amount": amount,
            "transaction_type": type,
            "category_id": categoryId,
            "description": description,
            "date": isoFormatter.string(from: date)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                if let error = error {
                    errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера"
                    showErrorAlert = true
                    return
                }
                showingAddSheet = false
                editingTransaction = nil
                loadTransactions()
                loadBalance()
            }
        }.resume()
    }
    
    func deleteTransaction(id: Int) {
        guard let token = authManager.token else {
            errorMessage = "Требуется авторизация"
            showErrorAlert = true
            return
        }
        let originalTransactions = allTransactions
        allTransactions.removeAll { $0.id == id }
        refreshTransactionDaySections()
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.allTransactions = originalTransactions
                    self.refreshTransactionDaySections()
                    errorMessage = "Не удалось удалить: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.allTransactions = originalTransactions
                    self.refreshTransactionDaySections()
                    errorMessage = "Ошибка сервера"
                    showErrorAlert = true
                    return
                }
                loadBalance()
            }
        }.resume()
    }
}

// --- КАРТОЧКА ТРАНЗАКЦИИ ---
struct TransactionCard: View {
    let t: BudgetView.Transaction
    var isLastInGroup: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FamilyAppStyle.softIconNeutral)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(typeTint)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(t.full_category_path ?? "Без категории")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(FamilyAppStyle.captionMuted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(TransactionCard.formatAmountStatic(t.amount, type: t.transaction_type))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(typeTint)
                if let b = t.balance {
                    Text(TransactionCard.formatBalanceOnCard(b))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FamilyAppStyle.pixsoInk)
                }
                Text(timeText)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(FamilyAppStyle.captionMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !isLastInGroup {
                Rectangle()
                    .fill(FamilyAppStyle.hairline)
                    .frame(height: 1)
            }
        }
    }

    private var typeTint: Color {
        t.transaction_type == "income" ? FamilyAppStyle.incomeGreen : FamilyAppStyle.expenseCoral
    }

    private var typeIcon: String {
        t.transaction_type == "income" ? "arrow.down.left" : "basket.fill"
    }

    private var defaultSubtitle: String {
        t.transaction_type == "income" ? "Поступление" : "Трата"
    }

    private var subtitleText: String {
        let base = defaultSubtitle
        let c = (t.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty { return base }
        return "\(base) | \(c)"
    }

    private var timeText: String {
        PVLDateParsing.timeHHmm(from: t.date)
    }
    
    static func formatAmountStatic(_ amount: Double, type: String) -> String {
        let absValue = abs(amount)
        let prefix = type == "income" ? "+₽ " : "−₽ "
        return prefix + String(format: "%.0f", absValue)
    }
    
    /// Накопленный баланс после этой операции (как на сервере: порядок date ↑, id ↑).
    static func formatBalanceOnCard(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let n = formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
        return "₽ \(n)"
    }
    
    static func formatDateStatic(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: d)
        }
        if let tIndex = string.firstIndex(of: "T") {
            let datePart = String(string[..<tIndex])
            let parts = datePart.split(separator: "-")
            if parts.count == 3 { return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2)))" }
            return datePart
        }
        return string
    }
}

// --- ЛИСТ ФИЛЬТРОВ (Обновлен под группы) ---
struct FilterSheet: View {
    @Binding var selectedDateFilter: BudgetView.DateFilter
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    @Binding var selectedGroupId: Int?       // НОВОЕ
    @Binding var selectedSubcategoryId: Int? // НОВОЕ
    
    @Binding var selectedUserId: Int?
    let users: [[String: Any]]
    
    let groups: [BudgetView.CategoryGroup]       // НОВОЕ
    let subcategories: [BudgetView.SubCategory]  // НОВОЕ
    
    @Binding var isPresented: Bool
    var onUpdate: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(action: { selectedUserId = nil; onUpdate() }) {
                        HStack { Text("Все пользователи"); Spacer(); if selectedUserId == nil { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) } }
                    }
                    ForEach(0..<users.count, id: \.self) { index in
                        let user = users[index]
                        if let id = user["id"] as? Int, let name = user["name"] as? String {
                            Button(action: { selectedUserId = id; onUpdate() }) {
                                HStack { Text(name); Spacer(); if selectedUserId == id { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) } }
                            }
                        }
                    }
                } header: { Text("Пользователь") } footer: {
                    Text("Только баланс в шапке. Ленту видят все; по дате и категориям — отдельно.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Section("Период") {
                    ForEach(BudgetView.DateFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedDateFilter = filter
                            if filter != .custom { onUpdate(); isPresented = false }
                        }) {
                            HStack { Text(filter.rawValue); Spacer(); if selectedDateFilter == filter { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) } }
                        }
                    }
                    if selectedDateFilter == .custom {
                        DatePicker("С:", selection: $startDate, displayedComponents: .date)
                        DatePicker("По:", selection: $endDate, displayedComponents: .date)
                        Button("Применить") { onUpdate(); isPresented = false }
                    }
                }
                
                Section("Категория") {
                    Button(action: {
                        selectedGroupId = nil
                        selectedSubcategoryId = nil
                        onUpdate()
                    }) {
                        HStack { Text("Все категории"); Spacer(); if selectedGroupId == nil { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) } }
                    }
                    
                    // Выбор Группы
                    if !groups.isEmpty {
                        Menu {
                            ForEach(groups) { group in
                                Button(action: {
                                    selectedGroupId = group.id
                                    selectedSubcategoryId = nil // Сброс подкатегории при смене группы
                                }) {
                                    HStack {
                                        Text(group.name)
                                        Spacer()
                                        if selectedGroupId == group.id && selectedSubcategoryId == nil { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedGroupId != nil ? (groups.first(where: { $0.id == selectedGroupId })?.name ?? "...") : "Выберите категорию")
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                    }
                    
                    // Выбор Подкатегории (если выбрана группа)
                    if selectedGroupId != nil && !subcategories.isEmpty {
                        Menu {
                            Button(action: { selectedSubcategoryId = nil; onUpdate() }) { Text("Все подкатегории") }
                            ForEach(subcategories) { sub in
                                Button(action: {
                                    selectedSubcategoryId = sub.id
                                    onUpdate()
                                }) {
                                    HStack {
                                        Text("↳ " + sub.name)
                                        Spacer()
                                        if selectedSubcategoryId == sub.id { Image(systemName: "checkmark").foregroundStyle(FamilyAppStyle.accent) }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedSubcategoryId != nil ? (subcategories.first(where: { $0.id == selectedSubcategoryId })?.name ?? "...") : "Все подкатегории")
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Сбросить все") {
                        selectedDateFilter = .all
                        selectedGroupId = nil
                        selectedSubcategoryId = nil
                        selectedUserId = nil
                        onUpdate()
                    }.foregroundColor(.red)
                }
            }
            .pvlFormScreenStyle()
            .tint(FamilyAppStyle.accent)
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { onUpdate(); isPresented = false } }
            }
        }
    }
}
