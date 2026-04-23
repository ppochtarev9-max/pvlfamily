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
    
    // Фильтр по пользователю
    @State private var selectedUserId: Int? = nil
    
    // Навигация
    @State private var navigateToDetails = false
    @State private var balanceDate = Date()
    @State private var showBalanceCalendar = false
    
    // Ошибки
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isSaving = false

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

    // Итоговый отфильтрованный список транзакций
    var filteredTransactions: [Transaction] {
        var result = allTransactions
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Фильтр по дате
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
                    guard let d = parseDate($0.date) else { return false }
                    return d >= startOfWeek && d <= now
                }
            }
        case .month:
            if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) {
                result = result.filter {
                    guard let d = parseDate($0.date) else { return false }
                    return d >= startOfMonth && d <= now
                }
            }
        case .custom:
            result = result.filter {
                guard let d = parseDate($0.date) else { return false }
                return d >= customStartDate && d <= customEndDate
            }
        }
        
        // 2. Фильтр по категории (Группа + Подкатегория)
        if let subId = selectedSubcategoryId {
            // Если выбрана конкретная подкатегория
            result = result.filter { $0.category_id == subId }
        } else if let groupId = selectedGroupId {
            // Если выбрана только группа, берем все её подкатегории
            let subIds = categoryGroups
                .first(where: { $0.id == groupId })?
                .subcategories.map { $0.id } ?? []
            result = result.filter { subIds.contains($0.category_id) }
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
    
    // --- МОДЕЛИ ДАННЫХ (Обновленные) ---
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
                // БЛОК 1: БАЛАНС
                ScrollView {
                    VStack(spacing: 16) {
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
                                selectedGroupId: $selectedGroupId,       // Обновлено
                                selectedSubcategoryId: $selectedSubcategoryId // Обновлено
                            )
                        }
                        Divider().padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground))
                }
                .frame(height: 280)
                
                // БЛОК 2: СПИСОК
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
            .navigationTitle("")
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
                            .foregroundColor(.blue)
                        }
                    }
                }
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
                    onUpdate: loadData
                )
            }
            .sheet(isPresented: $showingAddSheet) {
                TransactionFormView(
                    isPresented: $showingAddSheet,
                    categoryGroups: categoryGroups,          // Обновлено
                    transactionToEdit: editingTransactionId != nil ? allTransactions.first { $0.id == editingTransactionId } : nil,
                    onSave: { id, amount, type, catId, desc, date in
                        let finalCategoryId = catId ?? 17
                        saveTransaction(id: id, amount: amount, type: type, categoryId: finalCategoryId, description: desc, date: date)
                    },
                    onDelete: deleteTransaction
                )
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .onAppear(perform: loadData)
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
    
    func loadTransactions() {
        guard let token = authManager.token else {
            errorMessage = "Требуется авторизация"
            showErrorAlert = true
            return
        }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Нет соединения с сервером"
                    showErrorAlert = true
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера"
                    showErrorAlert = true
                    return
                }
                guard let data = data else { return }
                
                do {
                    let list = try JSONDecoder().decode([Transaction].self, from: data)
                    self.allTransactions = list
                } catch {
                    errorMessage = "Неверный формат данных"
                    showErrorAlert = true
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
    
    func startNewTransaction() { editingTransactionId = nil; showingAddSheet = true }
    func editTransaction(_ t: Transaction) { editingTransactionId = t.id; showingAddSheet = true }
    
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
                editingTransactionId = nil
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
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.allTransactions = originalTransactions
                    errorMessage = "Не удалось удалить: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.allTransactions = originalTransactions
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.full_category_path ?? "Без категории").font(.headline).fontWeight(.semibold).lineLimit(1)
                    if let desc = t.description, !desc.isEmpty {
                        Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Text(TransactionCard.formatAmountStatic(t.amount, type: t.transaction_type))
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(t.transaction_type == "income" ? .green : .red)
            }
            
            Divider().background(Color.gray.opacity(0.2))
            HStack {
                if let bal = t.balance {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Остаток").font(.caption2).foregroundColor(.secondary).textCase(.uppercase)
                        Text(String(format: "%.0f ₽", bal)).font(.title).fontWeight(.heavy)
                            .foregroundColor(bal >= 0 ? .blue : .orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TransactionCard.formatDateStatic(t.date)).font(.title3).foregroundColor(.gray)
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
    
    static func formatAmountStatic(_ amount: Double, type: String) -> String {
        let sign = ""
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
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
                Section("Пользователь") {
                    Button(action: { selectedUserId = nil; onUpdate() }) {
                        HStack { Text("Все пользователи"); Spacer(); if selectedUserId == nil { Image(systemName: "checkmark").foregroundColor(.blue) } }
                    }
                    ForEach(0..<users.count, id: \.self) { index in
                        let user = users[index]
                        if let id = user["id"] as? Int, let name = user["name"] as? String {
                            Button(action: { selectedUserId = id; onUpdate() }) {
                                HStack { Text(name); Spacer(); if selectedUserId == id { Image(systemName: "checkmark").foregroundColor(.blue) } }
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
                            HStack { Text(filter.rawValue); Spacer(); if selectedDateFilter == filter { Image(systemName: "checkmark").foregroundColor(.blue) } }
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
                        HStack { Text("Все категории"); Spacer(); if selectedGroupId == nil { Image(systemName: "checkmark").foregroundColor(.blue) } }
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
                                        if selectedGroupId == group.id && selectedSubcategoryId == nil { Image(systemName: "checkmark").foregroundColor(.blue) }
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
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { onUpdate(); isPresented = false } }
            }
        }
    }
}
