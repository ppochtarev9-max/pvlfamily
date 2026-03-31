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
        var children: [Category]? = []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView("Нет записей", systemImage: "list.bullet.rectangle", description: Text("Нажмите +, чтобы добавить операцию"))
                } else {
                    List {
                        ForEach(transactions) { t in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(t.category_name ?? "Без категории").font(.headline)
                                    Spacer()
                                    Text(formatAmount(t.amount, type: t.transaction_type))
                                        .fontWeight(.bold)
                                        .foregroundColor(colorForType(t.transaction_type))
                                }
                                if let desc = t.description, !desc.isEmpty {
                                    Text(desc).font(.subheadline).foregroundColor(.secondary)
                                }
                                HStack {
                                    Text(formatDate(t.date)).font(.caption2).foregroundColor(.gray)
                                    Text("•").font(.caption2).foregroundColor(.gray)
                                    Text(t.creator_name ?? "Неизвестно").font(.caption2).foregroundColor(.gray)
                                }
                            }
                            .swipeActions {
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
                    Button(action: { showingCategoriesManager = true }) { Image(systemName: "tag.fill") }
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
        }
    }
    
    func colorForType(_ type: String) -> Color {
        switch type { case "income": return .green; case "expense": return .red; default: return .primary }
    }
    func formatAmount(_ amount: Double, type: String) -> String {
        let sign = (type == "income") ? "+" : (type == "expense" ? "-" : "")
        return "\(sign)\(String(format: "%.2f", amount)) ₽"
    }
    func formatDate(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) {
            let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateStyle = .short; f.timeStyle = .short
            return f.string(from: date)
        }
        return string
    }
    
    func loadData() { loadCategories(); loadTransactions() }
    
    func loadTransactions() {
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
    
    func startNewTransaction() { editingTransactionId = nil; loadCategories(); showingAddSheet = true }
    func editTransaction(_ t: Transaction) { editingTransactionId = t.id; loadCategories(); showingAddSheet = true }
    
    func saveTransaction(id: Int?, amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = (id != nil) ? "PUT" : "POST"
        if let tid = id { req.url = URL(string: "\(authManager.baseURL)/budget/transactions/\(tid)") }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": iso.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { showingAddSheet = false; editingTransactionId = nil; loadTransactions() }
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
