import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var allTransactions: [Transaction] = []
    @State private var categories: [Category] = []
    
    // Состояния фильтров
    @State private var showingFilterSheet = false
    @State private var selectedDateFilter: DateFilter = .all
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    
    @State private var selectedCategoryId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil
    
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
            Group {
                if filteredTransactions.isEmpty {
                    ContentUnavailableView("Нет записей", systemImage: "list.bullet.rectangle", description: Text("Измените фильтры или добавьте операцию"))
                } else {
                    List {
                        ForEach(filteredTransactions) { t in
                            TransactionCard(t: t)
                                // Уменьшаем отступы между карточками
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .swipeActions {
                                    Button(role: .destructive) { deleteTransaction(id: t.id) } label: { Label("Удалить", systemImage: "trash") }
                                    Button { editTransaction(t) } label: { Label("Изменить", systemImage: "pencil") }.tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Бюджет")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingCategoriesManager = true }) {
                        Image(systemName: "tag.fill")
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
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheet(
                    selectedDateFilter: $selectedDateFilter,
                    startDate: $customStartDate,
                    endDate: $customEndDate,
                    selectedCategoryId: $selectedCategoryId,
                    selectedSubcategoryId: $selectedSubcategoryId,
                    categories: availableCategories,
                    subcategories: availableSubcategories,
                    isPresented: $showingFilterSheet
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
            .navigationDestination(isPresented: $showingCategoriesManager) {
                CategoriesManagerView(categories: $categories)
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
    
    var hasActiveFilters: Bool {
        selectedDateFilter != .all || selectedCategoryId != nil
    }
    
    @State private var showingAddSheet = false
    @State private var editingTransactionId: Int? = nil
    @State private var showingCategoriesManager = false
    
    func colorForType(_ type: String) -> Color {
        switch type { case "income": return .green; case "expense": return .red; default: return .primary }
    }
    func formatAmount(_ amount: Double, type: String) -> String {
        let sign = ""
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
    }
    func formatDate(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        // Убрали .withFractionalSeconds, теперь парсятся даты и с мс, и без
        iso.formatOptions = [.withInternetDateTime]
        
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: d)
        }
        
        // Фоллбэк на всякий случай (ручная обрезка)
        if let tIndex = string.firstIndex(of: "T") {
            let datePart = String(string[..<tIndex])
            let parts = datePart.split(separator: "-")
            if parts.count == 3 {
                return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2)))"
            }
            return datePart
        }
        return string
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
    
    func loadData() { loadCategories(); loadTransactions() }
    
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
            DispatchQueue.main.async { showingAddSheet = false; editingTransactionId = nil; loadTransactions() }
        }.resume()
    }
    
    func deleteTransaction(id: Int) {
        guard let token = authManager.token else { return }
        DispatchQueue.main.async { self.allTransactions.removeAll { $0.id == id } }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, error in
            if error != nil { DispatchQueue.main.async { loadTransactions() } }
        }.resume()
    }
}

// --- НОВЫЙ КОМПОНЕНТ: КАРТОЧКА ТРАНЗАКЦИИ (ОПТИМИЗИРОВАННАЯ) ---
struct TransactionCard: View {
    let t: BudgetView.Transaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Верхняя часть: Категория + Сумма операции
            HStack(alignment: .top, spacing: 12) {
                // Левая часть: Категория и описание
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.category_name ?? "Без категории")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    if let desc = t.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Правая часть: Сумма операции
                Text(formatAmount(t.amount, type: t.transaction_type))
                    .font(.title2) // Чуть меньше, чем было, чтобы не спорить с балансом
                    .fontWeight(.bold)
                    .foregroundColor(colorForType(t.transaction_type))
                    .multilineTextAlignment(.trailing)
            }
            
            Divider()
                .background(Color.gray.opacity(0.2))
            
            // Нижняя часть: БАЛАНС (крупно) + Метаданные
            HStack(alignment: .center) {
                // Крупный баланс
                if let bal = t.balance {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Остаток")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(String(format: "%.0f ₽", bal))
                            .font(.title) // КРУПНЫЙ ШРИФТ
                            .fontWeight(.heavy)
                            .foregroundColor(bal >= 0 ? .blue : .orange)
                    }
                }
                
                Spacer()
                
                // Метаданные (дата и автор) - компактно
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDate(t.date))
                        .font(.title3)
                        .foregroundColor(.gray)
                    
                    Text(t.creator_name ?? "Неизвестно")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(14) // Чуть меньше отступы внутри карточки
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(colorForType(t.transaction_type).opacity(0.15), lineWidth: 1)
        )
    }
    
    func colorForType(_ type: String) -> Color {
        switch type { case "income": return .green; case "expense": return .red; default: return .gray }
    }
    
    func formatAmount(_ amount: Double, type: String) -> String {
        let sign = ""
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
    }
    
    func formatDate(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        // Убрали .withFractionalSeconds, теперь парсятся даты и с мс, и без
        iso.formatOptions = [.withInternetDateTime]
        
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: d)
        }
        
        // Фоллбэк на всякий случай (ручная обрезка)
        if let tIndex = string.firstIndex(of: "T") {
            let datePart = String(string[..<tIndex])
            let parts = datePart.split(separator: "-")
            if parts.count == 3 {
                return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2)))"
            }
            return datePart
        }
        return string
    }
}

// --- ЛИСТ ФИЛЬТРОВ (Без изменений) ---
struct FilterSheet: View {
    @Binding var selectedDateFilter: BudgetView.DateFilter
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    @Binding var selectedCategoryId: Int?
    @Binding var selectedSubcategoryId: Int?
    
    let categories: [BudgetView.Category]
    let subcategories: [BudgetView.Category]
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    ForEach(BudgetView.DateFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedDateFilter = filter
                            if filter != .custom { isPresented = false }
                        }) {
                            HStack {
                                Text(filter.rawValue)
                                Spacer()
                                if selectedDateFilter == filter {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    if selectedDateFilter == .custom {
                        DatePicker("С:", selection: $startDate, displayedComponents: .date)
                        DatePicker("По:", selection: $endDate, displayedComponents: .date)
                        Button("Применить период") { isPresented = false }
                    }
                }
                
                Section("Категория") {
                    Button(action: {
                        selectedCategoryId = nil
                        selectedSubcategoryId = nil
                        isPresented = false
                    }) {
                        HStack {
                            Text("Все категории")
                            Spacer()
                            if selectedCategoryId == nil {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
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
                                        if selectedCategoryId == cat.id && selectedSubcategoryId == nil {
                                            Image(systemName: "checkmark").foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedCategoryId != nil ? (categories.first(where: { $0.id == selectedCategoryId })?.name ?? "Выберите...") : "Выберите категорию")
                                    .foregroundColor(selectedCategoryId != nil ? .primary : .secondary)
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                            }
                        }
                        
                        if selectedCategoryId != nil {
                            if subcategories.isEmpty {
                                Text("Нет подкатегорий").font(.caption).foregroundColor(.gray)
                            } else {
                                Menu {
                                    Button(action: {
                                        selectedSubcategoryId = nil
                                        isPresented = false
                                    }) {
                                        Text("Все подкатегории")
                                    }
                                    Divider()
                                    ForEach(subcategories) { sub in
                                        Button(action: {
                                            selectedSubcategoryId = sub.id
                                            isPresented = false
                                        }) {
                                            HStack {
                                                Text("↳ " + sub.name)
                                                Spacer()
                                                if selectedSubcategoryId == sub.id {
                                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedSubcategoryId != nil ? (subcategories.first(where: { $0.id == selectedSubcategoryId })?.name ?? "Выберите...") : "Все подкатегории")
                                            .foregroundColor(selectedSubcategoryId != nil ? .primary : .secondary)
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button("Сбросить все фильтры") {
                        selectedDateFilter = .all
                        selectedCategoryId = nil
                        selectedSubcategoryId = nil
                        isPresented = false
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { isPresented = false }
                }
            }
        }
    }
}
