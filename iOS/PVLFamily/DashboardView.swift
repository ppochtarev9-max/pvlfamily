import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Состояния для открытия шторок
    @State private var showingTransactionSheet = false
    @State private var showingEventSheet = false
    @State private var showingTrackerSheet = false
    
    // Данные и состояния загрузки
    @State private var transactionCategories: [BudgetView.Category] = []
    @State private var isLoadingCategories = false
    
    // Состояния ошибок и сохранения
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isSavingTransaction = false
    @State private var isSavingEvent = false
    @State private var isSavingLog = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
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
                        }
                        
                        // Событие
                        ActionCard(title: "Событие", icon: "calendar.badge.plus", color: .red) {
                            showingEventSheet = true
                        }
                    }
                    .padding(.horizontal)
                    
                    if isLoadingCategories {
                        ProgressView("Загрузка категорий...")
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Быстрые действия")
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
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
                AddEventView(
                    isPresented: $showingEventSheet,
                    onSave: createEvent,
                    isSaving: isSavingEvent
                )
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
    
    // --- Логика загрузки и сохранения ---
    
    func loadCategories() {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isLoadingCategories = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoadingCategories = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при загрузке категорий"
                    showErrorAlert = true
                    return
                }
                
                guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else {
                    errorMessage = "Ошибка обработки данных"
                    showErrorAlert = true
                    return
                }
                
                self.transactionCategories = list
                self.showingTransactionSheet = true
            }
        }.resume()
    }
    
    func saveTransaction(amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSavingTransaction = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSavingTransaction = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при создании транзакции"
                    showErrorAlert = true
                    return
                }
                
                showingTransactionSheet = false
            }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSavingEvent = true
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
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSavingEvent = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при создании события"
                    showErrorAlert = true
                    return
                }
                
                showingEventSheet = false
            }
        }.resume()
    }
    
    func saveLog(type: String, startTime: Date, endTime: Date?, note: String) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSavingLog = true
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
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSavingLog = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при сохранении записи"
                    showErrorAlert = true
                    return
                }
                
                showingTrackerSheet = false
            }
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
