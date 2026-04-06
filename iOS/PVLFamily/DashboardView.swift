import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Состояния для открытия шторок
    @State private var showingTransactionSheet = false
    @State private var showingEventSheet = false
    @State private var showingTrackerSheet = false
    
    // Для транзакции используем тип из BudgetView
    @State private var transactionCategories: [BudgetView.Category] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Заголовок
                    Text("Быстрые действия")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    // Сетка карточек
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        
                        // Сон
                        ActionCard(title: "Сон", icon: "moon.fill", color: .purple) {
                            showingTrackerSheet = true
                        }
                        
                        // Еда
                        ActionCard(title: "Еда", icon: "fork.knife", color: .orange) {
                            showingTrackerSheet = true
                        }
                        
                        // Памперс
                        ActionCard(title: "Памперс", icon: "drop.triangle.fill", color: .blue) {
                            showingTrackerSheet = true
                        }
                        
                        // Игра
                        ActionCard(title: "Игра", icon: "star.fill", color: .pink) {
                            showingTrackerSheet = true
                        }
                        
                        // Транзакция
                        ActionCard(title: "Транзакция", icon: "dollarsign.circle.fill", color: .green) {
                            loadCategories()
                            showingTransactionSheet = true
                        }
                        
                        // Событие
                        ActionCard(title: "Событие", icon: "calendar.badge.plus", color: .red) {
                            showingEventSheet = true
                        }
                    }
                    .padding(.horizontal)
                    
                }
                .padding(.vertical)
            }
            .navigationTitle("Главная")
            .sheet(isPresented: $showingTransactionSheet) {
                TransactionFormView(
                    isPresented: $showingTransactionSheet,
                    categories: transactionCategories,
                    transactionToEdit: nil,
                    onSave: { _, amount, type, catId, desc, date in
                        saveTransaction(amount: amount, type: type, categoryId: catId, description: desc, date: date)
                    },
                    onDelete: { _ in }
                )
            }
            .sheet(isPresented: $showingEventSheet) {
                AddEventView(isPresented: $showingEventSheet, onSave: createEvent)
            }
            .sheet(isPresented: $showingTrackerSheet) {
                TrackerFormView(
                    isPresented: $showingTrackerSheet,
                    existingLog: nil,
                    onSave: { type, start, end, note in
                        saveLog(type: type, startTime: start, endTime: end, note: note)
                    },
                    onDelete: { _ in }
                )
            }
        }
    }
    
    // --- Логика сохранения ---
    
    func loadCategories() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
            DispatchQueue.main.async { transactionCategories = list }
        }.resume()
    }
    
    func saveTransaction(amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { showingTransactionSheet = false }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else { return }
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events" : "\(authManager.baseURL)/calendar/events"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "title": title,
            "description": desc,
            "event_date": isoFormatter.string(from: date),
            "event_type": type
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { showingEventSheet = false }
        }.resume()
    }
    
    func saveLog(type: String, startTime: Date, endTime: Date?, note: String) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "event_type": type,
            "start_time": isoFormatter.string(from: startTime)
        ]
        if let end = endTime {
            body["end_time"] = isoFormatter.string(from: end)
        }
        if !note.isEmpty {
            body["note"] = note
        }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { showingTrackerSheet = false }
        }.resume()
    }
}

// --- Компонент карточки действия ---
struct ActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}
