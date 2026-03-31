import SwiftUI

struct BudgetView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var transactions: [Transaction] = []
    @State private var categories: [Category] = []
    @State private var showingAddSheet = false
    @State private var newAmount = ""
    @State private var selectedCategoryId: Int?
    @State private var newDesc = ""
    
    struct Transaction: Identifiable, Codable {
        let id: Int
        let amount: Double
        let description: String?
        let date: String
        let category_name: String
        let category_type: String
    }
    
    struct Category: Identifiable, Codable {
        let id: Int
        let name: String
        let type: String
    }
    
    var body: some View {
        NavigationView {
            Group {
                if transactions.isEmpty {
                    Text("Нет транзакций. Добавьте первую!")
                        .foregroundColor(.gray)
                } else {
                    List {
                        ForEach(transactions) { t in
                            VStack(alignment: .leading) {
                                Text(t.description ?? "Без описания")
                                    .font(.headline)
                                HStack {
                                    Text("\(t.amount, specifier: "%.2f") ₽")
                                        .fontWeight(.bold)
                                        .foregroundColor(t.category_type == "expense" ? .red : .green)
                                    Spacer()
                                    Text(t.category_name)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Бюджет")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        loadCategories()
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addTransactionSheet()
            }
            .onAppear(perform: loadTransactions)
        }
    }
    
    func loadTransactions() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let list = try? JSONDecoder().decode([Transaction].self, from: data) else { return }
            DispatchQueue.main.async { transactions = list }
        }.resume()
    }
    
    func loadCategories() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let list = try? JSONDecoder().decode([Category].self, from: data) else { return }
            DispatchQueue.main.async {
                categories = list
                if !categories.isEmpty { selectedCategoryId = categories[0].id }
            }
        }.resume()
    }
    
    func addTransactionSheet() -> some View {
        NavigationView {
            Form {
                TextField("Сумма", text: $newAmount)
                    .keyboardType(.decimalPad)
                Picker("Категория", selection: $selectedCategoryId) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                }
                TextField("Описание", text: $newDesc)
            }
            .navigationTitle("Новая запись")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { showingAddSheet = false } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { saveTransaction() }
                }
            }
        }
    }
    
    func saveTransaction() {
        guard let amount = Double(newAmount), let catId = selectedCategoryId, let token = authManager.token else { return }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["amount": amount, "category_id": catId, "description": newDesc]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                newAmount = ""
                newDesc = ""
                loadTransactions()
            }
        }.resume()
    }
}
