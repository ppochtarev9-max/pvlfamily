import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var transactions: [Transaction] = []
    @State private var categories: [Category] = []
    @State private var showingAddSheet = false
    @State private var editingTransactionId: Int? = nil
    @State private var showingCategoriesManager = false
    
    struct Transaction: Identifiable, Codable {
        let id: Int
        let amount: Double
        let transaction_type: String
        let category_id: Int
        let description: String?
        let date: String
        let creator_name: String?
        let category_name: String?
    }
    
    struct Category: Identifiable, Codable {
        let id: Int
        let name: String
        let type: String
        let parent_id: Int?
        var children: [Category]?
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView("Нет записей", systemImage: "list.bullet.rectangle", description: Text("Нажмите +, чтобы добавить операцию"))
                } else {
                    List {
                        ForEach(transactions) { t in
                            // Внутри BudgetView.swift, в List -> ForEach -> VStack
                            VStack(alignment: .leading, spacing: 6) {
                                // Верхняя строка: Категория и Сумма
                                HStack {
                                    Text(t.category_name ?? "Без категории")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(formatAmount(t.amount, type: t.transaction_type))
                                        .fontWeight(.bold)
                                        .foregroundColor(colorForType(t.transaction_type))
                                }
                                
                                // Вторая строка: Описание (если есть)
                                if let desc = t.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Третья строка: Мета-данные (Дата, Автор, Тип категории)
                                HStack {
                                    Text(formatDate(t.date))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(t.creator_name ?? "Неизвестно") // Используем creator_name
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .contentShape(Rectangle()) // Чтобы свайп работал по всей площади
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleteTransaction(id: t.id) } label: { Label("Удалить", systemImage: "trash") }
                                Button { editTransaction(t) } label: { Label("Изменить", systemImage: "pencil") }.tint(.blue)
                            }
                        }
                    }
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
                    Button(action: { startNewTransaction() }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                TransactionFormView(
                    isPresented: $showingAddSheet,
                    categories: categories,
                    transactionToEdit: editingTransactionId != nil ? transactions.first { $0.id == editingTransactionId } : nil,
                    onSave: { id, amount, type, catId, desc, date in // <-- добавь date сюда
                        saveTransaction(id: id, amount: amount, type: type, categoryId: catId, description: desc, date: date)
                    },
                    onDelete: deleteTransaction
                                )
            }
            .navigationDestination(isPresented: $showingCategoriesManager) {
                CategoriesManagerView(categories: $categories)
            }
            .onAppear(perform: loadData)
        }
    }
    
    func loadData() {
        loadCategories()
        loadTransactions()
    }
    
    func colorForType(_ type: String) -> Color {
        switch type { case "income": return .green; case "expense": return .red; case "transfer": return .blue; default: return .primary }
    }
    func formatAmount(_ amount: Double, type: String) -> String {
        let sign = (type == "income") ? "+" : (type == "expense" ? "-" : "")
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
    }
    
    func formatDate(_ string: String) -> String {
        // Список возможных форматов от сервера
        let formatters: [String] = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", // С микросекундами
            "yyyy-MM-dd'T'HH:mm:ss",        // Стандарт ISO
            "yyyy-MM-dd HH:mm:ss",          // Пробел вместо T
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"    // С таймзоной
        ]
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var date: Date? = isoFormatter.date(from: string)
        
        // Если стандартный не сработал, пробуем вручную
        if date == nil {
            for fmt in formatters {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = fmt
                if let d = df.date(from: string) {
                    date = d
                    break
                }
            }
        }
        
        // Финальное форматирование для пользователя
        if let finalDate = date {
            let outFormatter = DateFormatter()
            outFormatter.locale = Locale(identifier: "ru_RU")
            outFormatter.dateStyle = .short
            outFormatter.timeStyle = .short
            return outFormatter.string(from: finalDate)
        }
        
        return string // Возврат исходной строки если совсем беда
    }
    func loadTransactions() {
        print("👤 Текущий пользователь: \(authManager.userName ?? "nil")")
        print("🎫 Токен: \(authManager.token ?? "nil")")

        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([Transaction].self, from: data) else { return }
            DispatchQueue.main.async { transactions = list }
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
    
    func startNewTransaction() {
        editingTransactionId = nil
        loadCategories() // Обновляем категории перед открытием
        showingAddSheet = true
    }
    
    func editTransaction(_ t: Transaction) {
        editingTransactionId = t.id
        loadCategories()
        showingAddSheet = true
    }
    
    func saveTransaction(id: Int?, amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { return }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = (id != nil) ? "PUT" : "POST"
        
        if let tid = id {
            req.url = URL(string: "\(authManager.baseURL)/budget/transactions/\(tid)")
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Конвертируем дату в ISO8601
        let isoFormatter = ISO8601DateFormatter()
        let dateString = isoFormatter.string(from: date)
        
        var body: [String: Any] = [
            "amount": amount,
            "transaction_type": type,
            "category_id": categoryId,
            "description": description,
            "date": dateString // Отправляем дату явно
        ]
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                editingTransactionId = nil
                loadTransactions()
            }
        }.resume()
    }
    
    func deleteTransaction(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { loadTransactions() }
        }.resume()
    }
}
