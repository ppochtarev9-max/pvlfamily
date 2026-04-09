import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Состояния для открытия шторок (Транзакция, Событие)
    @State private var showingTransactionSheet = false
    @State private var showingEventSheet = false
    
    // Данные для транзакций
    @State private var transactionCategories: [BudgetView.Category] = []
    @State private var isLoadingCategories = false
    
    // Состояния ошибок и сохранения
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isSavingTransaction = false
    @State private var isSavingEvent = false
    
    // --- СОСТОЯНИЯ ТРЕКЕРА ---
    @State private var trackerStatus: TrackerStatus?
    @State private var isSleeping: Bool = false
    @State private var sleepStartTime: Date?
    @State private var lastWakeUpTime: Date?
    
    // Таймер
    @State private var timer: Timer?
    @State private var elapsedSeconds: Int = 0
    
    // Флаг первой загрузки
    @State private var hasLoadedInitialStatus = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. ВИДЖЕТ УПРАВЛЕНИЯ СНОМ И КОРМЛЕНИЕМ
                    TrackerStatusWidget(
                        isSleeping: isSleeping,
                        elapsedSeconds: elapsedSeconds,
                        onStartSleep: {
                            // ОПТИМИСТИЧНОЕ ОБНОВЛЕНИЕ: меняем UI сразу
                            let oldState = isSleeping
                            let oldRef = isSleeping ? sleepStartTime : lastWakeUpTime
                            
                            isSleeping = true
                            sleepStartTime = Date()
                            lastWakeUpTime = nil
                            resetTimerImmediate(referenceDate: sleepStartTime!)
                            
                            // Запрос на сервер
                            authManager.startSleep { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success(let status):
                                        // Синхронизируем с ответом сервера (для надежности)
                                        syncWithStatus(status)
                                    case .failure(let error):
                                        // ОТКАТ при ошибке
                                        isSleeping = oldState
                                        if oldState { sleepStartTime = oldRef } else { lastWakeUpTime = oldRef }
                                        resetTimerImmediate(referenceDate: oldState ? (oldRef ?? Date()) : (oldRef ?? Date()))
                                        
                                        errorMessage = "Ошибка запуска сна: \(error.localizedDescription)"
                                        showErrorAlert = true
                                    }
                                }
                            }
                        },
                        onFinishSleep: {
                            // ОПТИМИСТИЧНОЕ ОБНОВЛЕНИЕ: меняем UI сразу
                            let oldState = isSleeping
                            let oldRef = isSleeping ? sleepStartTime : lastWakeUpTime
                            
                            isSleeping = false
                            lastWakeUpTime = Date()
                            sleepStartTime = nil
                            resetTimerImmediate(referenceDate: lastWakeUpTime!)
                            
                            // Запрос на сервер
                            finishCurrentSleepOptimistic()
                        },
                        onQuickFeed: {
                            authManager.quickFeed { result in
                                DispatchQueue.main.async {
                                    if case .failure(let error) = result {
                                        errorMessage = "Ошибка записи кормления: \(error.localizedDescription)"
                                        showErrorAlert = true
                                    }
                                    // Кормление не меняет состояние сна/бодрствования, таймер не сбрасываем
                                }
                            }
                        }
                    )
                    .padding(.horizontal)
                    
                    Divider().padding(.horizontal)
                    
                    // 2. ОСТАЛЬНЫЕ ДЕЙСТВИЯ
                    Text("Другие действия")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ActionCard(title: "Транзакция", icon: "dollarsign.circle.fill", color: .green) {
                            loadCategories()
                        }
                        
                        ActionCard(title: "Событие", icon: "calendar.badge.plus", color: .red) {
                            showingEventSheet = true
                        }
                    }
                    .padding(.horizontal)
                    
                    if isLoadingCategories {
                        ProgressView("Загрузка категорий...")
                            .padding()
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Главная")
            .onAppear {
                if !hasLoadedInitialStatus {
                    loadTrackerStatus()
                    hasLoadedInitialStatus = true
                } else {
                    startTimer()
                }
            }
            .refreshable {
                hasLoadedInitialStatus = false
                loadTrackerStatus()
            }
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
        }
    }
    
    // --- ЛОГИКА ТРЕКЕРА ---
    
    func loadTrackerStatus() {
        authManager.getTrackerStatus { result in
            DispatchQueue.main.async {
                if case .success(let status) = result {
                    syncWithStatus(status)
                } else if case .failure(let error) = result {
                    print("⚠️ Ошибка загрузки статуса: \(error)")
                }
            }
        }
    }
    
    // Синхронизация состояния с данными сервера
    func syncWithStatus(_ status: TrackerStatus) {
        self.trackerStatus = status
        let newState = status.is_sleeping
        
        // Обновляем даты
        let formatter = ISO8601DateFormatter()
        var newRefDate: Date? = nil
        
        if newState {
            if let startStr = status.current_sleep_start, let d = formatter.date(from: startStr) {
                self.sleepStartTime = d
                newRefDate = d
            } else {
                self.sleepStartTime = Date()
                newRefDate = Date()
            }
            self.lastWakeUpTime = nil
        } else {
            self.sleepStartTime = nil
            if let wakeStr = status.last_wake_up, let d = formatter.date(from: wakeStr) {
                self.lastWakeUpTime = d
                newRefDate = d
            } else {
                self.lastWakeUpTime = Date()
                newRefDate = Date()
            }
        }
        
        // Сбрасываем таймер только если состояние реально изменилось относительно текущего UI
        if self.isSleeping != newState {
            self.isSleeping = newState
            if let ref = newRefDate {
                resetTimerImmediate(referenceDate: ref)
            }
        }
    }
    
    func finishCurrentSleepOptimistic() {
        guard let status = trackerStatus, let sleepId = status.current_sleep_id else {
            // Если ID нет в кэше, пробуем загрузить статус снова или показываем ошибку
            errorMessage = "Не найден активный сон. Попробуйте обновить экран."
            showErrorAlert = true
            // Откат UI уже сделан в замыкании кнопки, но тут можно усилить
            return
        }
        
        authManager.finishSleep(sleepId: sleepId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    syncWithStatus(status)
                case .failure(let error):
                    // ОТКАТ при ошибке завершения (возвращаем состояние сна)
                    // Для простоты просто перезагружаем статус с сервера, чтобы быть точными
                    loadTrackerStatus()
                    errorMessage = "Ошибка завершения сна: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // Мгновенный сброс таймера (для оптимистичного UI)
    func resetTimerImmediate(referenceDate: Date) {
        elapsedSeconds = 0
        let diff = Date().timeIntervalSince(referenceDate)
        if diff > 0 {
            elapsedSeconds = Int(diff)
        }
        startTimer()
    }
    
    // --- ЛОГИКА ТРАНЗАКЦИЙ И СОБЫТИЙ ---
    
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
                    errorMessage = "Ошибка сервера"
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
                isSavingTransaction = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера"
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
                    errorMessage = "Ошибка сервера"
                    showErrorAlert = true
                    return
                }
                
                showingEventSheet = false
            }
        }.resume()
    }
}

// --- ВИДЖЕТ СОСТОЯНИЯ РЕБЕНКА ---
struct TrackerStatusWidget: View {
    let isSleeping: Bool
    let elapsedSeconds: Int
    let onStartSleep: () -> Void
    let onFinishSleep: () -> Void
    let onQuickFeed: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: isSleeping ? "moon.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(isSleeping ? .purple : .orange)
                
                Text(isSleeping ? "Ребенок спит" : "Ребенок бодрствует")
                    .font(.headline)
                
                Spacer()
            }
            
            Text(formattedElapsedTime())
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(isSleeping ? .purple : .orange)
                .monospacedDigit()
            
            HStack(spacing: 12) {
                if isSleeping {
                    Button(action: onFinishSleep) {
                        Label("Завершить сон", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else {
                    Button(action: onStartSleep) {
                        Label("Начать сон", systemImage: "moon.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    
                    Button(action: onQuickFeed) {
                        Image(systemName: "drop.fill")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    func formattedElapsedTime() -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// --- КОМПОНЕНТ КАРТОЧКИ ДЕЙСТВИЯ ---
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
