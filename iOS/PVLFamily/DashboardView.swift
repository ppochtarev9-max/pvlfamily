import SwiftUI
import UserNotifications
import ActivityKit

// --- ГЛОБАЛЬНЫЕ ФУНКЦИИ РАЗРЕШЕНИЙ ---
func requestLiveActivityPermission() {
    Task {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted == true { print("✅ Разрешения на уведомления получены") }
        
        let authStatus = ActivityAuthorizationInfo().areActivitiesEnabled
        if authStatus { print("✅ Live Activities разрешены") }
    }
}

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var notificationManager: NotificationManager
    
    // Состояния UI
    @State private var showingTransactionSheet = false
    @State private var showingEventSheet = false
    @State private var transactionCategories: [BudgetView.Category] = []
    @State private var isLoadingCategories = false
    
    // Ошибки
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // --- СОСТОЯНИЯ ТРЕКЕРА (Единый источник истины) ---
    @State private var trackerStatus: TrackerStatus?
    @State private var isSleeping: Bool = false
    @State private var sleepStartTime: Date?
    @State private var lastWakeUpTime: Date?
    
    // Таймер
    @State private var timer: Timer?
    @State private var elapsedSeconds: Int = 0
    
    // Флаги управления
    @State private var hasLoadedInitialStatus = false
    @State private var isSyncing = false // Защита от гонок запросов
    @State private var isViewActive = false
    
    // Live Activity
    @State private var currentActivity: Activity<SleepActivityAttributes>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    TrackerStatusWidget(
                        isSleeping: isSleeping,
                        elapsedSeconds: elapsedSeconds,
                        onStartSleep: { startSleepAction() },
                        onFinishSleep: { finishSleepAction() },
                        onQuickFeed: { performQuickFeed() }
                    )
                    .padding(.horizontal)
                    
                    Divider().padding(.horizontal)
                    
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
                        ProgressView("Загрузка категорий...").padding()
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Главная")
            .onOpenURL { url in handleDeepLink(url) }
            
            // ЖИЗНЕННЫЙ ЦИКЛ
            .onAppear {
                if !hasLoadedInitialStatus {
                    loadTrackerStatus()
                    hasLoadedInitialStatus = true
                } else {
                    recalculateTimer()
                    startTimer()
                }
                isViewActive = true
            }
            .onDisappear {
                isViewActive = false
                // Таймер оставляем, если идет активность, чтобы обновлять виджет
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                isViewActive = true
                recalculateTimer()
                startTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                isViewActive = false
            }
            
            // REFRESH: Не сбрасываем hasLoadedInitialStatus, чтобы не потерять состояние таймера
            .refreshable {
                await loadTrackerStatusAsync()
            }
            
            .onReceive(NotificationCenter.default.publisher(for: .trackerDataUpdated)) { _ in
                loadTrackerStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { notification in
                guard let action = notification.userInfo?["action"] as? String else { return }
                switch action {
                case "start_sleep": startSleepAction()
                case "finish_sleep": finishSleepAction()
                case "quick_feed": performQuickFeed()
                default: break
                }
            }
            
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
                if errorMessage?.contains("Сессия истекла") == true {
                    Button("Выйти", role: .destructive) { authManager.logout() }
                }
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
                    isSaving: false
                )
            }
        }
    }
    
    // --- ЛОГИКА ---
    
    func loadTrackerStatus() {
        guard !isSyncing else { return } // Защита от повторного вызова
        isSyncing = true
        
        authManager.getTrackerStatus { result in
            DispatchQueue.main.async {
                isSyncing = false
                handleTrackerResult(result)
            }
        }
    }
    
    func loadTrackerStatusAsync() async {
        guard !isSyncing else { return }
        isSyncing = true
        
        await withCheckedContinuation { continuation in
            authManager.getTrackerStatus { result in
                DispatchQueue.main.async {
                    handleTrackerResult(result)
                    continuation.resume()
                }
            }
        }
    }
    
    func handleTrackerResult(_ result: Result<TrackerStatus, Error>) {
        switch result {
        case .success(let status):
            syncWithStatus(status)
        case .failure(let error):
            print("⚠️ Ошибка статуса: \(error.localizedDescription)")
            var isUnauthorized = false
            if let apiError = error as? APIError {
                if case .unauthorized = apiError { isUnauthorized = true }
            }
            
            if isUnauthorized {
                errorMessage = "Сессия истекла."
                showErrorAlert = true
            } else if isViewActive {
                errorMessage = "Нет связи с сервером."
                showErrorAlert = true
            }
        }
    }
    
    func syncWithStatus(_ status: TrackerStatus) {
        let newState = status.is_sleeping
        let formatter = ISO8601DateFormatter()
        var newRefDate: Date? = nil
        
        if newState {
            if let startStr = status.current_sleep_start, let d = formatter.date(from: startStr) {
                self.sleepStartTime = d; newRefDate = d
            } else {
                self.sleepStartTime = Date(); newRefDate = Date()
            }
            self.lastWakeUpTime = nil
        } else {
            self.sleepStartTime = nil
            if let wakeStr = status.last_wake_up, let d = formatter.date(from: wakeStr) {
                self.lastWakeUpTime = d; newRefDate = d
            } else {
                self.lastWakeUpTime = Date(); newRefDate = Date()
            }
        }
        
        // Если состояние изменилось (сон <-> бодрствование)
        if self.isSleeping != newState {
            self.isSleeping = newState
            if let ref = newRefDate { recalculateTimer(referenceDate: ref) }
            
            if newState {
                if let ref = newRefDate { startLiveActivity(startTime: ref) }
            } else {
                // Не завершаем, а обновляем виджет в режиме бодрствования
            }
        } else {
            // Состояние то же, просто синхронизируем время (коррекция рассинхрона)
            if let ref = newRefDate { recalculateTimer(referenceDate: ref) }
        }
        
        if isViewActive && timer == nil { startTimer() }
    }
    
    func recalculateTimer(referenceDate: Date? = nil) {
        let ref = referenceDate ?? (isSleeping ? (sleepStartTime ?? Date()) : (lastWakeUpTime ?? Date()))
        let diff = Date().timeIntervalSince(ref)
        elapsedSeconds = max(0, Int(diff))
    }
    
    func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            if currentActivity != nil {
                updateLiveActivity(elapsed: elapsedSeconds)
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // --- ДЕЙСТВИЯ ---
    
    func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "start_sleep": startSleepAction()
        case "finish_sleep": finishSleepAction()
        case "quick_feed": performQuickFeed()
        default: break
        }
    }
    
    func startSleepAction() {
        guard !isSyncing else { return }
        let oldState = isSleeping
        let oldRef = isSleeping ? sleepStartTime : lastWakeUpTime
        
        isSleeping = true
        sleepStartTime = Date()
        lastWakeUpTime = nil
        recalculateTimer(referenceDate: sleepStartTime!)
        
        authManager.startSleep { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    syncWithStatus(status)
                    scheduleSleepNotificationIfNeeded()
                case .failure(let error):
                    // Откат
                    isSleeping = oldState
                    if oldState { sleepStartTime = oldRef } else { lastWakeUpTime = oldRef }
                    if let ref = oldRef { recalculateTimer(referenceDate: ref) }
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    func finishSleepAction() {
        guard !isSyncing else { return }
        guard let status = trackerStatus, let sleepId = status.current_sleep_id else {
            errorMessage = "Активный сон не найден."
            showErrorAlert = true
            return
        }
        
        let oldRef = sleepStartTime
        isSleeping = false
        lastWakeUpTime = Date()
        sleepStartTime = nil
        recalculateTimer(referenceDate: lastWakeUpTime!)
        
        authManager.finishSleep(sleepId: sleepId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    syncWithStatus(status)
                case .failure(let error):
                    loadTrackerStatus() // Принудительная перезагрузка
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    func performQuickFeed() {
        guard !isSyncing else { return }
        authManager.quickFeed { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    func scheduleSleepNotificationIfNeeded() {
        let content = UNMutableNotificationContent()
        content.title = "Малыш спит уже 2 часа"
        content.body = "Проверьте, все ли в порядке."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7200, repeats: false)
        let request = UNNotificationRequest(identifier: "sleep_check_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("❌ Ошибка уведомления: \(error)") }
        }
    }
    
    // --- LIVE ACTIVITY ---
    
    func startLiveActivity(startTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        if let activity = currentActivity ?? Activity<SleepActivityAttributes>.activities.first {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                self.currentActivity = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    forceStartLiveActivity(startTime: startTime)
                }
            }
            return
        }
        forceStartLiveActivity(startTime: startTime)
    }
    
    private func forceStartLiveActivity(startTime: Date) {
        let attributes = SleepActivityAttributes(childName: "Малыш")
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: true, startTime: startTime, elapsedSeconds: 0, statusText: "Сон начался"
        )
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            self.currentActivity = activity
        } catch { print("❌ Ошибка Live Activity: \(error)") }
    }
    
    func updateLiveActivity(elapsed: Int) {
        let activityToUpdate = currentActivity ?? Activity<SleepActivityAttributes>.activities.first
        guard let activity = activityToUpdate else { return }
        
        let statusText = isSleeping ? "Спит" : "Бодрствует"
        let iconStartTime = isSleeping ? (sleepStartTime ?? Date()) : (lastWakeUpTime ?? Date())
        
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: isSleeping, startTime: iconStartTime, elapsedSeconds: elapsed, statusText: statusText
        )
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        Task { await activity.update(content) }
    }
    
    // --- ТРАНЗАКЦИИ И СОБЫТИЯ (без изменений) ---
    func loadCategories() {
        guard let token = authManager.token else { errorMessage = "Нет авторизации"; showErrorAlert = true; return }
        isLoadingCategories = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoadingCategories = false
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
                self.transactionCategories = list
                self.showingTransactionSheet = true
            }
        }.resume()
    }
    
    func saveTransaction(amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { errorMessage = "Нет авторизации"; showErrorAlert = true; return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingTransactionSheet = false
            }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else { errorMessage = "Нет авторизации"; showErrorAlert = true; return }
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events" : "\(authManager.baseURL)/calendar/events"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = ["title": title, "description": desc, "event_date": isoFormatter.string(from: date), "event_type": type]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingEventSheet = false
            }
        }.resume()
    }
}

// --- ВИДЖЕТЫ ---
struct TrackerStatusWidget: View {
    let isSleeping: Bool; let elapsedSeconds: Int
    let onStartSleep: () -> Void; let onFinishSleep: () -> Void; let onQuickFeed: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: isSleeping ? "moon.fill" : "sun.max.fill")
                    .font(.title2).foregroundColor(isSleeping ? .purple : .orange)
                Text(isSleeping ? "Ребенок спит" : "Ребенок бодрствует").font(.headline)
                Spacer()
            }
            Text(formattedElapsedTime())
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(isSleeping ? .purple : .orange)
                .monospacedDigit()
            HStack(spacing: 12) {
                if isSleeping {
                    Button(action: onFinishSleep) {
                        Label("Завершить сон", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.purple)
                } else {
                    Button(action: onStartSleep) {
                        Label("Начать сон", systemImage: "moon.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.purple)
                    Button(action: onQuickFeed) {
                        Image(systemName: "drop.fill").font(.title2).frame(width: 50, height: 50)
                    }.buttonStyle(.bordered).tint(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    func formattedElapsedTime() -> String {
        let h = elapsedSeconds / 3600; let m = (elapsedSeconds % 3600) / 60; let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
struct ActionCard: View {
    let title: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack { Circle().fill(color.opacity(0.15)).frame(width: 60, height: 60); Image(systemName: icon).font(.title).foregroundColor(color) }
                Text(title).font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
            }.frame(maxWidth: .infinity).frame(height: 120).background(Color(.systemBackground)).cornerRadius(20).shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}
extension Notification.Name {
    static let trackerDataUpdated = Notification.Name("trackerDataUpdated")
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
}
