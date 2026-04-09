import SwiftUI
import UserNotifications
import ActivityKit // <-- 1. ИМПОРТ ДЛЯ LIVE ACTIVITY

func requestLiveActivityPermission() {
    Task {
        // Запрос прав на уведомления (обязательно для активностей)
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        if granted == true {
            print("✅ Разрешения на уведомления получены")
        } else {
            print("⚠️ Пользователь отклонил уведомления")
        }
        
        // Проверка статуса Live Activities
        let authStatus = ActivityAuthorizationInfo().areActivitiesEnabled
        if authStatus {
            print("✅ Live Activities разрешены")
        } else {
            print("⚠️ Live Activities запрещены в настройках")
            // Здесь можно показать пользователю алерт с инструкцией, как включить в Настройках
        }
    }
}


struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var notificationManager: NotificationManager
    
    // Состояния для открытия шторок
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
    
    // Ссылка на текущую активность (чтобы обновлять её)
    @State private var currentActivity: Activity<SleepActivityAttributes>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. ВИДЖЕТ УПРАВЛЕНИЯ СНОМ И КОРМЛЕНИЕМ
                    TrackerStatusWidget(
                        isSleeping: isSleeping,
                        elapsedSeconds: elapsedSeconds,
                        onStartSleep: {
                            startSleepAction()
                        },
                        onFinishSleep: {
                            finishSleepAction()
                        },
                        onQuickFeed: {
                            authManager.quickFeed { result in
                                DispatchQueue.main.async {
                                    if case .failure(let error) = result {
                                        errorMessage = "Ошибка записи кормления: \(error.localizedDescription)"
                                        showErrorAlert = true
                                    }
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
                    recalculateTimer()
                    startTimer()
                }
                let status = ActivityAuthorizationInfo().areActivitiesEnabled
                if !status {
                    print("⚠️ Live Activities отключены в настройках системы")
                }
                //if !hasLoadedInitialStatus {
                //     notificationManager.requestLiveActivityPermission() // или вызови напрямую
                // }
            }
            .onDisappear {
                // Не останавливаем таймер полностью, если активность идет, но можно оптимизировать
                // stopTimer()
            }
            .refreshable {
                hasLoadedInitialStatus = false
                loadTrackerStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackerDataUpdated)) { _ in
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
    
    func syncWithStatus(_ status: TrackerStatus) {
        self.trackerStatus = status
        let newState = status.is_sleeping
        
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
        
        if self.isSleeping != newState {
            self.isSleeping = newState
            if let ref = newRefDate {
                recalculateTimer(referenceDate: ref)
            }
            // Если состояние изменилось, возможно, нужно обновить или завершить Activity
            // Но это лучше делать в явных действиях пользователя (start/finish)
        } else {
            if let ref = newRefDate {
                recalculateTimer(referenceDate: ref)
            }
        }
    }
    
    func startSleepAction() {
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
                     self.syncWithStatus(status)
                     self.scheduleSleepNotificationIfNeeded()
                     
                     // ПРОВЕРКА И ЗАПУСК LIVE ACTIVITY
                     Task {
                         let authInfo = ActivityAuthorizationInfo()
                         // areActivitiesEnabled возвращает true, если функция доступна и разрешена
                         if authInfo.areActivitiesEnabled {
                             self.startLiveActivity(startTime: self.sleepStartTime ?? Date())
                         } else {
                             print("⚠️ Live Activities отключены в настройках устройства или недоступны")
                             // Можно показать пользователю алерт с инструкцией
                         }
                     }
                     
                 case .failure(let error):
                     // ОТКАТ состояния UI
                     isSleeping = oldState
                     if oldState {
                         sleepStartTime = oldRef
                     } else {
                         lastWakeUpTime = oldRef
                     }
                     
                     // Пересчет таймера для возврата к старому времени
                     if let ref = oldRef {
                         recalculateTimer(referenceDate: ref)
                     }
                     
                     // Показ ошибки пользователю
                     errorMessage = "Ошибка запуска сна: \(error.localizedDescription)"
                     showErrorAlert = true
                     
                     // Гарантируем, что активность не запущена при ошибке
                     if let activity = currentActivity {
                         Task {
                             await activity.end(nil, dismissalPolicy: .immediate)
                             self.currentActivity = nil
                         }
                     }
                 }
             }
         }
    }
    
    func finishSleepAction() {
        let oldState = isSleeping
        let oldRef = isSleeping ? sleepStartTime : lastWakeUpTime
        
        isSleeping = false
        lastWakeUpTime = Date()
        sleepStartTime = nil
        recalculateTimer(referenceDate: lastWakeUpTime!)
        
        guard let status = trackerStatus, let sleepId = status.current_sleep_id else {
            errorMessage = "Не найден активный сон."
            showErrorAlert = true
            isSleeping = true
            sleepStartTime = oldRef
            lastWakeUpTime = nil
            if let ref = oldRef { recalculateTimer(referenceDate: ref) }
            return
        }
        
        authManager.finishSleep(sleepId: sleepId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    syncWithStatus(status)
                    
                    // ЗАВЕРШЕНИЕ LIVE ACTIVITY
                    endLiveActivity(durationMinutes: Int(elapsedSeconds / 60))
                    
                case .failure(let error):
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
            // Обновляем Live Activity каждую секунду для тиканья таймера
            if isSleeping {
                updateLiveActivity(elapsed: elapsedSeconds)
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func recalculateTimer(referenceDate: Date? = nil) {
        let ref = referenceDate ?? (isSleeping ? (sleepStartTime ?? Date()) : (lastWakeUpTime ?? Date()))
        let diff = Date().timeIntervalSince(ref)
        elapsedSeconds = diff > 0 ? Int(diff) : 0
        if timer == nil && hasLoadedInitialStatus {
             startTimer()
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
    
    // --- LIVE ACTIVITY METHODS ---
    
    func startLiveActivity(startTime: Date) {
        print("🔍 [APP] Попытка запуска Live Activity...")
        
        let authInfo = ActivityAuthorizationInfo()
        print("🔍 [APP] Статус разрешений: \(authInfo.areActivitiesEnabled)")
        
        guard authInfo.areActivitiesEnabled else {
            print("❌ [APP] Live Activities запрещены системой!")
            return
        }
        
        let attributes = SleepActivityAttributes(childName: "Малыш")
        print("🔍 [APP] Атрибуты созданы: \(attributes.childName)")
        
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: true,
            startTime: startTime,
            elapsedSeconds: 0,
            statusText: "🚀 Старт активности!"
        )
        
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        do {
             print("📡 [APP] Отправка запроса Activity.request...")
             let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
             self.currentActivity = activity
             print("✅ [APP] Activity успешно запрошена! ID: \(activity.id)")
             print("📄 [APP] Статус активности: \(activity.activityState)")
         } catch {
             print("❌ [APP] Ошибка при запросе Activity: \(error.localizedDescription)")
             print("❌ [APP] Детали ошибки: \(error)")
         }
    }
    
    func updateLiveActivity(elapsed: Int) {
        // Ищем активность
        let activityToUpdate = currentActivity ?? Activity<SleepActivityAttributes>.activities.first
        guard let activity = activityToUpdate else { return }
        
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: true,
            startTime: sleepStartTime ?? Date(),
            elapsedSeconds: elapsed,
            statusText: "Спит"
        )
        
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        Task {
            await activity.update(content)
        }
    }
    
    func endLiveActivity(durationMinutes: Int) {
        let activityToEnd = currentActivity ?? Activity<SleepActivityAttributes>.activities.first
        guard let activity = activityToEnd else { return }
        
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: false,
            startTime: lastWakeUpTime ?? Date(),
            elapsedSeconds: durationMinutes * 60,
            statusText: "Сон завершен"
        )
        
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
            self.currentActivity = nil
            print("✅ Live Activity завершена")
        }
    }
    
    // --- ЛОГИКА ТРАНЗАКЦИЙ И СОБЫТИЙ (без изменений) ---
    func loadCategories() { /* ... тот же код ... */
        guard let token = authManager.token else { errorMessage = "Пользователь не авторизован"; showErrorAlert = true; return }
        isLoadingCategories = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoadingCategories = false
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { errorMessage = "Ошибка сервера"; showErrorAlert = true; return }
                guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { errorMessage = "Ошибка данных"; showErrorAlert = true; return }
                self.transactionCategories = list; self.showingTransactionSheet = true
            }
        }.resume()
    }
    
    func saveTransaction(amount: Double, type: String, categoryId: Int, description: String, date: Date) { /* ... тот же код ... */
        guard let token = authManager.token else { errorMessage = "Пользователь не авторизован"; showErrorAlert = true; return }
        isSavingTransaction = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"; req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSavingTransaction = false
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { errorMessage = "Ошибка сервера"; showErrorAlert = true; return }
                showingTransactionSheet = false
            }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) { /* ... тот же код ... */
        guard let token = authManager.token else { errorMessage = "Пользователь не авторизован"; showErrorAlert = true; return }
        isSavingEvent = true
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events" : "\(authManager.baseURL)/calendar/events"
        var req = URLRequest(url: URL(string: urlStr)!); req.httpMethod = "POST"; req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = ["title": title, "description": desc, "event_date": isoFormatter.string(from: date), "event_type": type]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSavingEvent = false
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { errorMessage = "Ошибка сервера"; showErrorAlert = true; return }
                showingEventSheet = false
            }
        }.resume()
    }
}

// --- ВИДЖЕТ СОСТОЯНИЯ РЕБЕНКА (без изменений) ---
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
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
}
