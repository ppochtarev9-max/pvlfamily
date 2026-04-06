import SwiftUI

// MARK: - 🟢 ГЛАВНЫЙ ВИД: BUDGET VIEW
struct BudgetView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var allTransactions: [Transaction] = []
    @State private var categories: [Category] = []
    
    // Состояния фильтров (ОБЩИЕ для баланса и списка)
    @State private var showingFilterSheet = false
    @State private var selectedDateFilter: DateFilter = .all
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    
    @State private var selectedCategoryId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil
    
    // Для баланса
    @State private var summary: DashboardSummary?
    @State private var isLoadingBalance = false
    
    // Фильтр по пользователю (теперь общий)
    @State private var selectedUserId: Int? = nil
    
    // Навигация
    @State private var navigateToDetails = false
    
    // Для выбора даты баланса
    @State private var balanceDate = Date()
    @State private var showBalanceCalendar = false

    // Вычисляемые свойства для доступных опций
    var availableCategories: [Category] {
        categories.filter { $0.parent_id == nil }.sorted { $0.name < $1.name }
    }
    
    var availableSubcategories: [Category] {
        guard let catId = selectedCategoryId else { return [] }
        return categories.filter { $0.parent_id == catId }.sorted { $0.name < $1.name }
    }
    
    // Итоговый отфильтрованный список
    var filteredTransactions: [Transaction] {
        var result = allTransactions
        
        // 1. Фильтр по дате
        let now = Date()
        let calendar = Calendar.current
        
        switch selectedDateFilter {
        case .all: break
        case .today:
            result = result.filter { isSameDay(dateString: $0.date, to: now) }
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
            result = result.filter { isSameDay(dateString: $0.date, to: yesterday) }
        case .week:
            guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return [] }
            result = result.filter {
                guard let d = parseDate($0.date) else { return false }
                return d >= startOfWeek && d <= now
            }
        case .month:
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return [] }
            result = result.filter {
                guard let d = parseDate($0.date) else { return false }
                return d >= startOfMonth && d <= now
            }
        case .custom:
            result = result.filter {
                guard let d = parseDate($0.date) else { return false }
                return d >= customStartDate && d <= customEndDate
            }
        }
        
        // 2. Фильтр по категории
        if let catId = selectedCategoryId {
            var targetIds: Set<Int> = [catId]
            if let subId = selectedSubcategoryId {
                targetIds = [subId]
            } else {
                let children = categories.filter { $0.parent_id == catId }.map { $0.id }
                targetIds.formUnion(children)
            }
            result = result.filter { targetIds.contains($0.category_id) }
        }
        
        return result
    }
    
    enum DateFilter: String, CaseIterable {
        case all = "Все даты"
        case today = "Сегодня"
        case yesterday = "Вчера"
        case week = "Эта неделя"
        case month = "Этот месяц"
        case custom = "Выбрать период..."
    }
    
    struct Transaction: Identifiable, Codable {
        let id: Int
        let amount: Double
        let transaction_type: String
        let category_id: Int
        let description: String?
        let date: String
        let creator_name: String?
        let category_name: String?
        let balance: Double?
    }
    
    struct Category: Identifiable, Codable {
        let id: Int
        let name: String
        let type: String
        let parent_id: Int?
        let is_hidden: Bool?
        var children: [Category]? = []
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // ================================================================
                // 🔹 БЛОК 1: ВЕРХНЯЯ ЧАСТЬ (БАЛАНС + КНОПКА ДЕТАЛИЗАЦИИ)
                // ================================================================
                ScrollView {
                    VStack(spacing: 16) {
                                                
                        // --- 1.2 Карточка баланса ---
                        VStack(spacing: 16) {
                            if let s = summary {
                                Text(formatCurrency(s.balance))
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(s.balance >= 0 ? .blue : .red)
                                
                                HStack(spacing: 30) {
                                    VStack {
                                        Text("Доходы").font(.caption).foregroundColor(.secondary)
                                        Text(formatCurrency(s.total_income)).foregroundColor(.green).fontWeight(.semibold)
                                    }
                                    Divider().frame(height: 30)
                                    VStack {
                                        Text("Расходы").font(.caption).foregroundColor(.secondary)
                                        Text(formatCurrency(s.total_expense)).foregroundColor(.red).fontWeight(.semibold)
                                    }
                                }
                            } else if isLoadingBalance {
                                ProgressView()
                            } else {
                                Text("Нет данных").foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal)
                        
                        // --- 1.3 Кнопка Детализация ---
                        Button(action: { navigateToDetails = true }) {
                            Text("Детализация")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .navigationDestination(isPresented: $navigateToDetails) {
                            BudgetDetailsView(
                                selectedUserId: $selectedUserId,
                                selectedDateFilter: $selectedDateFilter,
                                customStartDate: $customStartDate,
                                customEndDate: $customEndDate,
                                selectedCategoryId: $selectedCategoryId,
                                selectedSubcategoryId: $selectedSubcategoryId
                            )
                        }
                        
                        Divider().padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground))
                }
                .frame(height: 280) // Фиксированная высота шапки
                
                // ================================================================
                // 🔹 БЛОК 2: СПИСОК ТРАНЗАКЦИЙ
                // ================================================================
                Group {
                    if filteredTransactions.isEmpty {
                        ContentUnavailableView("Нет записей", systemImage: "list.bullet.rectangle", description: Text("Измените фильтры или добавьте операцию"))
                    } else {
                        List {
                            ForEach(filteredTransactions) { t in
                                TransactionCard(t: t)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .swipeActions {
                                        Button(role: .destructive) { deleteTransaction(id: t.id) } label: { Label("Удалить", systemImage: "trash") }
                                        Button { editTransaction(t) } label: { Label("Изменить", systemImage: "pencil") }.tint(.blue)
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("") // Скрыли стандартный заголовок
            .toolbar {
                // --- ЛЕВАЯ ЧАСТЬ: ЗАГОЛОВОК С КАЛЕНДАРЕМ ---
                ToolbarItem(placement: .principal) { // Используем .principal для центрального заголовка
                    HStack(spacing: 4) {
                        Text("Бюджет на ")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary) // Явно задаем цвет
                        
                        Button(action: { showBalanceCalendar = true }) {
                            HStack(spacing: 2) {
                                Text(formatDateShort(balanceDate))
                                    .fontWeight(.medium)
                                Image(systemName: "calendar")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                // --- ПРАВАЯ ЧАСТЬ: ФИЛЬТР И ПЛЮС ---
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 15) {
                        Button(action: { showingFilterSheet = true }) {
                            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .foregroundColor(hasActiveFilters ? .blue : .gray)
                        }
                        Button(action: { startNewTransaction() }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            // --- ШТОРКА КАЛЕНДАРЯ (ВНЕ toolbar, но внутри NavigationStack) ---
            .sheet(isPresented: $showBalanceCalendar) {
                VStack(spacing: 20) {
                    DatePicker("", selection: $balanceDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: balanceDate) { _ in
                            showBalanceCalendar = false
                            loadBalance()
                        }
                    
                    Button("Закрыть") {
                        showBalanceCalendar = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 20)
                }
                .presentationDetents([.medium])
            }            .sheet(isPresented: $showingFilterSheet) {
                 FilterSheet(
                     selectedDateFilter: $selectedDateFilter,
                     startDate: $customStartDate,
                     endDate: $customEndDate,
                     selectedCategoryId: $selectedCategoryId,
                     selectedSubcategoryId: $selectedSubcategoryId,
                     selectedUserId: $selectedUserId,
                     users: authManager.users,
                     categories: availableCategories,
                     subcategories: availableSubcategories,
                     isPresented: $showingFilterSheet,
                     onUpdate: loadData
                 )
             }
            .sheet(isPresented: $showingAddSheet) {
                TransactionFormView(
                    isPresented: $showingAddSheet,
                    categories: categories,
                    transactionToEdit: editingTransactionId != nil ? allTransactions.first { $0.id == editingTransactionId } : nil,
                    onSave: { id, amount, type, catId, desc, date in
                        saveTransaction(id: id, amount: amount, type: type, categoryId: catId, description: desc, date: date)
                    },
                    onDelete: deleteTransaction
                )
            }
            .onAppear(perform: loadData)
            .refreshable {
                await withCheckedContinuation { continuation in
                    loadData()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // ================================================================
    // 🔹 ВСПОМОГАТЕЛЬНЫЕ ПЕРЕМЕННЫЕ И ФУНКЦИИ
    // ================================================================
    
    var hasActiveFilters: Bool {
        selectedDateFilter != .all || selectedCategoryId != nil || selectedUserId != nil
    }
    
    @State private var showingAddSheet = false
    @State private var editingTransactionId: Int? = nil
    
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
        guard let d = parseDate(dateString) else { return false }
        return Calendar.current.isDate(d, inSameDayAs: date)
    }
    
    func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: string)
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: abs(value))) ?? "0") ₽"
    }
    
    func loadData() {
        print("🔄 [Budget] Загрузка данных (User: \(selectedUserId == nil ? "All" : "\(selectedUserId!)"))")
        loadBalance()
        loadCategories()
        loadTransactions()
    }
    
    func loadBalance() {
        isLoadingBalance = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: balanceDate) // Используем выбранную дату
        
        authManager.getDashboardSummary(asOfDate: dateStr, userId: selectedUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data): self.summary = data
                case .failure(let error): print("Ошибка баланса: \(error)")
                }
                self.isLoadingBalance = false
            }
        }
    }
    
    func loadTransactions() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([Transaction].self, from: data) else { return }
            DispatchQueue.main.async { self.allTransactions = list }
        }.resume()
    }
    
    func loadCategories() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([Category].self, from: data) else { return }
            DispatchQueue.main.async { categories = list }
        }.resume()
    }
    
    func startNewTransaction() { editingTransactionId = nil; loadCategories(); showingAddSheet = true }
    func editTransaction(_ t: Transaction) { editingTransactionId = t.id; loadCategories(); showingAddSheet = true }
    
    func saveTransaction(id: Int?, amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = (id != nil) ? "PUT" : "POST"
        if let tid = id { req.url = URL(string: "\(authManager.baseURL)/budget/transactions/\(tid)") }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { showingAddSheet = false; editingTransactionId = nil; loadTransactions(); loadBalance() }
        }.resume()
    }
    
    func deleteTransaction(id: Int) {
        guard let token = authManager.token else { return }
        DispatchQueue.main.async { self.allTransactions.removeAll { $0.id == id } }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, error in
            if error != nil { DispatchQueue.main.async { loadTransactions(); loadBalance() } }
        }.resume()
    }
}

// ================================================================
// 🔹 ПОДВИДЫ (SUBVIEWS)
// ================================================================

// --- КАРТОЧКА ТРАНЗАКЦИИ ---
struct TransactionCard: View {
    let t: BudgetView.Transaction
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.category_name ?? "Без категории").font(.headline).fontWeight(.semibold).lineLimit(1)
                    if let desc = t.description, !desc.isEmpty {
                        Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Text(formatAmount(t.amount, type: t.transaction_type))
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(t.transaction_type == "income" ? .green : .red)
            }
            Divider().background(Color.gray.opacity(0.2))
            HStack(alignment: .center) {
                if let bal = t.balance {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Остаток").font(.caption2).foregroundColor(.secondary).textCase(.uppercase)
                        Text(String(format: "%.0f ₽", bal)).font(.title).fontWeight(.heavy)
                            .foregroundColor(bal >= 0 ? .blue : .orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDate(t.date)).font(.title3).foregroundColor(.gray)
                    Text(t.creator_name ?? "Неизвестно").font(.title3).foregroundColor(.gray)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((t.transaction_type == "income" ? Color.green : Color.red).opacity(0.15), lineWidth: 1))
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
}

// --- ЛИСТ ФИЛЬТРОВ ---
struct FilterSheet: View {
    @Binding var selectedDateFilter: BudgetView.DateFilter
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    @Binding var selectedCategoryId: Int?
    @Binding var selectedSubcategoryId: Int?
    
    @Binding var selectedUserId: Int?
    let users: [[String: Any]]
    
    let categories: [BudgetView.Category]
    let subcategories: [BudgetView.Category]
    @Binding var isPresented: Bool
    
    var onUpdate: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Пользователь") {
                    Button(action: {
                        selectedUserId = nil
                        onUpdate()
                    }) {
                        HStack {
                            Text("Все пользователи")
                            Spacer()
                            if selectedUserId == nil { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                    }
                    ForEach(0..<users.count, id: \.self) { index in
                        let user = users[index]
                        if let id = user["id"] as? Int, let name = user["name"] as? String {
                            Button(action: {
                                selectedUserId = id
                                onUpdate()
                            }) {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    if selectedUserId == id { Image(systemName: "checkmark").foregroundColor(.blue) }
                                }
                            }
                        }
                    }
                }
                
                Section("Период") {
                    ForEach(BudgetView.DateFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedDateFilter = filter
                            if filter != .custom { onUpdate(); isPresented = false }
                        }) {
                            HStack {
                                Text(filter.rawValue)
                                Spacer()
                                if selectedDateFilter == filter { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
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
                        selectedCategoryId = nil
                        selectedSubcategoryId = nil
                        onUpdate()
                    }) {
                        HStack {
                            Text("Все категории")
                            Spacer()
                            if selectedCategoryId == nil { Image(systemName: "checkmark").foregroundColor(.blue) }
                        }
                    }
                    if !categories.isEmpty {
                        Menu {
                            ForEach(categories) { cat in
                                Button(action: {
                                    selectedCategoryId = cat.id
                                    selectedSubcategoryId = nil
                                }) {
                                    HStack {
                                        Text(cat.name)
                                        Spacer()
                                        if selectedCategoryId == cat.id && selectedSubcategoryId == nil { Image(systemName: "checkmark").foregroundColor(.blue) }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedCategoryId != nil ? (categories.first(where: { $0.id == selectedCategoryId })?.name ?? "...") : "Выберите категорию")
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                        if selectedCategoryId != nil {
                            if !subcategories.isEmpty {
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
                                                if selectedSubcategoryId == sub.id { Image(systemName: "checkmark").foregroundColor(.blue) }
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
                    }
                }
                
                Section {
                    Button("Сбросить все") {
                        selectedDateFilter = .all
                        selectedCategoryId = nil
                        selectedSubcategoryId = nil
                        selectedUserId = nil
                        onUpdate()
                    }.foregroundColor(.red)
                }
            }
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { onUpdate(); isPresented = false } }
            }
        }
    }
}

#Preview {
    BudgetView()
        .environmentObject(AuthManager())
}
