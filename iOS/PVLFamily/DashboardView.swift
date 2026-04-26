import SwiftUI
import UserNotifications
import ActivityKit

/// Разбор дат из `/tracker/status` (Python `isoformat`, дроби, `Z`, offset).
/// «Голый» `ISO8601DateFormatter()` без опций часто возвращает `nil` → якорь сбрасывали в `Date()` и таймер показывал 00:00.
fileprivate enum TrackerAPIDate {
    static func parse(_ string: String?) -> Date? {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return nil }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone, .withFractionalSeconds]
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        if let d = f.date(from: trimmed) { return d }
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let d = df.date(from: trimmed) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df.date(from: trimmed) { return d }
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: trimmed)
    }
}

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
    @State private var transactionCategories: [BudgetView.CategoryGroup] = [] // ИСПРАВЛЕНО: CategoryGroup
    @State private var isLoadingCategories = false
    
    // Ошибки
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // --- СОСТОЯНИЯ ТРЕКЕРА ---
    @State private var trackerStatus: TrackerStatus?
    @State private var isSleeping: Bool = false
    @State private var sleepStartTime: Date?
    @State private var lastWakeUpTime: Date?
    @State private var lastUpdated: Date?

    // Флаги управления
    @State private var hasLoadedInitialStatus = false
    @State private var isSyncing = false
    
    // Live Activity
    @State private var currentActivity: Activity<SleepActivityAttributes>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 🔥 БАННЕР ОФФЛАЙН
                    if errorMessage?.contains("Нет связи") == true {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.white)
                            Text("Нет связи с сервером.")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: {
                                print("🔄 [USER] Нажата кнопка обновления (FORCE).")
                                loadTrackerStatus(force: true)
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                            .disabled(isSyncing)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    // ✅ ВИДЖЕТ ТРЕКЕРА
                    TrackerStatusWidget(
                        isSleeping: isSleeping,
                        referenceDate: isSleeping ? sleepStartTime : lastWakeUpTime,
                        onStartSleep: { startSleepAction() },
                        onFinishSleep: { finishSleepAction() },
                        onQuickFeed: { performQuickFeed() }
                    )
                    .padding(.horizontal)
                    
                    Text("Другие действия")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ActionCard(
                            title: "Транзакция",
                            subtitle: "Добавить запись",
                            icon: "receipt",
                            iconBackground: FamilyAppStyle.softIconGreen,
                            iconColor: .green
                        ) {
                            loadCategories()
                        }
                        ActionCard(
                            title: "Событие",
                            subtitle: "Новая запись",
                            icon: "calendar.badge.plus",
                            iconBackground: FamilyAppStyle.softIconOrange,
                            iconColor: .orange
                        ) {
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
            .background(FamilyAppStyle.screenBackground)
            .navigationTitle("Главная")
            .onOpenURL { url in handleDeepLink(url) }
            
            // ЖИЗНЕННЫЙ ЦИКЛ
            .onAppear {
                print("👁️ [LIFECYCLE] Dashboard появился на экране (onAppear).")
                if !hasLoadedInitialStatus {
                    loadTrackerStatus()
                    hasLoadedInitialStatus = true
                }
                if isSleeping || lastWakeUpTime != nil {
                    updateLiveActivityIfTracking()
                }
            }
            .onDisappear {
                print("👁️ [LIFECYCLE] Dashboard исчез с экрана (onDisappear).")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                print("☀️ [LIFECYCLE] Приложение возвращается на передний план.")
                if isSleeping || lastWakeUpTime != nil {
                    updateLiveActivityIfTracking()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                print("🌙 [LIFECYCLE] Приложение ушло в фон.")
            }
            
            .refreshable {
                print("🔄 [UI] Pull-to-refresh запущен.")
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
            
            .alert("Внимание", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
                
                if errorMessage?.contains("Нет связи") == true || errorMessage?.contains("Ошибка сети") == true {
                    Button("Попробовать снова") {
                        loadTrackerStatus()
                    }
                }
                
                if errorMessage?.contains("Сессия истекла") == true {
                    Button("Выйти", role: .destructive) {
                        authManager.logout()
                    }
                }
            } message: {
                Text(errorMessage ?? "Произошла неизвестная ошибка.")
            }
            
            .sheet(isPresented: $showingTransactionSheet) {
                // ИСПРАВЛЕНО: передача categoryGroups
                TransactionFormView(
                    isPresented: $showingTransactionSheet,
                    categoryGroups: transactionCategories,
                    transactionToEdit: nil,
                    onSave: { _, amount, type, catId, desc, date in
                        let finalCategoryId = catId ?? 17
                        saveTransaction(amount: amount, type: type, categoryId: finalCategoryId, description: desc, date: date)
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
    
    // --- Live Activity: подписка на `Text(..., .timer)` в extension — тикает без фонового Timer ---

    @MainActor
    func updateLiveActivityIfTracking() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard isSleeping || lastWakeUpTime != nil else { return }
        updateLiveActivity()
    }

    // --- ОБЩАЯ ЛОГИКА ---
    
    func loadTrackerStatus(force: Bool = false) {
        if force {
            isSyncing = false
            print("🔨 [FORCE] Принудительный сброс блокировки.")
        }
        guard !isSyncing else { return }
        
        print("📡 [NETWORK] Начало запроса статуса...")
        isSyncing = true
        
        authManager.getTrackerStatus { result in
            DispatchQueue.main.async {
                self.isSyncing = false
                print("🔓 [NETWORK] Запрос завершен.")
                self.handleTrackerResult(result)
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
            print("✅ [SUCCESS] Статус получен. Сон: \(status.is_sleeping)")
            if errorMessage?.contains("Нет связи") == true || errorMessage?.contains("Ошибка сети") == true {
                print("🟢 [RECOVERY] Связь восстановлена! Очищаем ошибку.")
                errorMessage = nil
                showErrorAlert = false
            }
            syncWithStatus(status)
        case .failure(let error):
            print("❌ [ERROR] Ошибка: \(error.localizedDescription)")
            var isNetworkError = false
            var isUnauthorized = false
            
            if let apiError = error as? APIError {
                if case .networkError = apiError { isNetworkError = true }
                if case .serverError = apiError { isNetworkError = true }
                if case .unauthorized = apiError { isUnauthorized = true }
            } else if (error as? URLError)?.code == .notConnectedToInternet {
                isNetworkError = true
            }
            
            if isUnauthorized {
                errorMessage = "Сессия истекла."
                showErrorAlert = true
            } else if isNetworkError {
                errorMessage = "Нет связи с сервером."
                if !showErrorAlert { showErrorAlert = true }
            } else {
                errorMessage = "Ошибка: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    func syncWithStatus(_ status: TrackerStatus) {
        print("🔄 [SYNC] Синхронизация... Было: \(isSleeping ? "Сон" : "Бод"), Стало: \(status.is_sleeping ? "Сон" : "Бод")")
        
        let newState = status.is_sleeping
        var newRefDate: Date? = nil
        
        if newState {
            // Сон: якорь — начало текущего сна.
            if let d = TrackerAPIDate.parse(status.current_sleep_start) {
                self.sleepStartTime = d
                newRefDate = d
            } else if let keep = self.sleepStartTime {
                // API не отдало время старта или строка не распарсилась — не сбрасываем таймер на «сейчас».
                newRefDate = keep
            } else {
                self.sleepStartTime = Date()
                newRefDate = self.sleepStartTime
            }
            self.lastWakeUpTime = nil
        } else {
            // Бодрствование: на сервере `last_wake_up` = end_time последнего завершённого сна = момент пробуждения.
            self.sleepStartTime = nil
            if let d = TrackerAPIDate.parse(status.last_wake_up) {
                self.lastWakeUpTime = d
                newRefDate = d
            } else if let keep = self.lastWakeUpTime {
                newRefDate = keep
            } else {
                self.lastWakeUpTime = nil
            }
        }
        
        if self.isSleeping != newState {
            print("🔄 [STATE CHANGE] Смена состояния!")
            self.isSleeping = newState
            if newState {
                if let ref = newRefDate { startLiveActivity(startTime: ref) }
            } else {
                // остаёмся в режиме бодрствования; LA обновим ниже
            }
        }
        
        if (isSleeping || lastWakeUpTime != nil) && (currentActivity == nil && Activity<SleepActivityAttributes>.activities.isEmpty) {
            let ref: Date? = isSleeping ? sleepStartTime : lastWakeUpTime
            if let ref {
                print("🆘 [FIX] Активность потеряна, пересоздаем...")
                startLiveActivity(startTime: ref)
            }
        }

        if isSleeping || lastWakeUpTime != nil {
            updateLiveActivityIfTracking()
        }
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
    
    @MainActor
    func startSleepAction() {
        guard !isSyncing else { return }
        isSleeping = true
        sleepStartTime = Date()
        lastWakeUpTime = nil
        
        authManager.startSleep { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    syncWithStatus(status)
                    scheduleSleepNotificationIfNeeded()
                case .failure(let error):
                    isSleeping = false
                    sleepStartTime = nil
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    @MainActor
    func finishSleepAction() {
        authManager.getTrackerStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.syncWithStatus(status)
                    guard let sleepId = status.current_sleep_id else {
                        self.errorMessage = "Активный сон не найден."
                        self.showErrorAlert = true
                        return
                    }
                    self.isSleeping = false
                    self.lastWakeUpTime = Date()
                    self.sleepStartTime = nil
                    
                    self.authManager.finishSleep(sleepId: sleepId) { finishResult in
                        DispatchQueue.main.async {
                            switch finishResult {
                            case .success(let finalStatus):
                                self.syncWithStatus(finalStatus)
                            case .failure(let error):
                                self.loadTrackerStatus()
                                self.errorMessage = "Ошибка завершения: \(error.localizedDescription)"
                                self.showErrorAlert = true
                            }
                        }
                    }
                case .failure(let error):
                    self.errorMessage = "Не удалось получить статус: \(error.localizedDescription)"
                    self.showErrorAlert = true
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
        let statusText = isSleeping ? "Сон начался" : "Бодрствование"
        
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: isSleeping,
            startTime: startTime,
            statusText: statusText,
            lastUpdated: Date()
        )
        let content = ActivityContent(state: contentState, staleDate: nil)
        
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            self.currentActivity = activity
            print("✅ Live Activity создана")
        } catch { print("❌ Ошибка создания Live Activity: \(error)") }
    }
    
    @MainActor
    func updateLiveActivity() {
        let activityToUpdate = currentActivity ?? Activity<SleepActivityAttributes>.activities.first
        guard let activity = activityToUpdate else { return }
        
        let statusText = isSleeping ? "Спит" : "Бодрствует"
        let iconStartTime: Date? = isSleeping ? sleepStartTime : lastWakeUpTime
        guard let iconStartTime else {
            print("⚠️ [LA] Нет якоря времени — пропуск обновления Live Activity")
            return
        }

        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: isSleeping,
            startTime: iconStartTime,
            statusText: statusText,
            lastUpdated: Date()
        )
        let content = ActivityContent(state: contentState, staleDate: nil)

        Task {
            do {
                try await activity.update(content)
            } catch {
                print("❌ Ошибка обновления виджета: \(error)")
            }
        }
    }
    
    // --- ТРАНЗАКЦИИ И СОБЫТИЯ (ИСПРАВЛЕНО) ---
    
    func loadCategories() {
        guard let token = authManager.token else {
            handleNetworkError("Нет авторизации")
            return
        }
        isLoadingCategories = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/groups")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoadingCategories = false
                if let error = error {
                    handleNetworkError(error.localizedDescription)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    return
                }
                guard let data = data else { return }
                
                do {
                    // ИСПРАВЛЕНО: декодируем в CategoryGroup
                    let list = try JSONDecoder().decode([BudgetView.CategoryGroup].self, from: data)
                    self.transactionCategories = list
                    self.showingTransactionSheet = true
                } catch {
                    print("❌ Ошибка декодирования категорий: \(error)")
                }
            }
        }.resume() // ИСПРАВЛЕНО: скобка на месте
    }
    
    func saveTransaction(amount: Double, type: String, categoryId: Int, description: String, date: Date) {
        guard let token = authManager.token else { handleNetworkError("Нет авторизации"); return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isoFormatter = ISO8601DateFormatter()
        let body: [String: Any] = ["amount": amount, "transaction_type": type, "category_id": categoryId, "description": description, "date": isoFormatter.string(from: date)]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { handleNetworkError(error.localizedDescription); return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingTransactionSheet = false
                // Можно добавить обновление списка транзакций если он открыт
            }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else { handleNetworkError("Нет авторизации"); return }
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
                if let error = error { handleNetworkError(error.localizedDescription); return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingEventSheet = false
            }
        }.resume()
    }
    
    func handleNetworkError(_ msg: String) {
        print("❌ [NETWORK] Ошибка операции: \(msg)")
        if !msg.contains("авторизации") {
             errorMessage = "Нет связи с сервером."
             if !showErrorAlert { showErrorAlert = true }
        } else {
             errorMessage = msg
             showErrorAlert = true
        }
    }
}

// --- ВИДЖЕТЫ ---
struct TrackerStatusWidget: View {
    let isSleeping: Bool
    /// Начало интервала: сон — `sleepStart`, бодрствование — момент пробуждения (`last_wake_up` с API).
    let referenceDate: Date?
    let onStartSleep: () -> Void
    let onFinishSleep: () -> Void
    let onQuickFeed: () -> Void
    private var accent: Color { FamilyAppStyle.accent }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text(isSleeping ? "Ребёнок спит" : "Ребёнок бодрствует")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text(referenceDate.map { "с \($0.pvlShortTime)" } ?? "")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundColor(Color(.secondaryLabel))
            }

            Group {
                if let ref = referenceDate {
                    Text(ref, style: .timer)
                        .foregroundColor(.primary)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(referenceDate.map { "Начало: \($0.pvlStartLabel)" } ?? "Начало: —")
                .font(.system(size: 13))
                .italic()
                .foregroundColor(Color(.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(FamilyAppStyle.cardStroke.opacity(0.9))
                .frame(height: 1)

            HStack(spacing: 12) {
                if isSleeping {
                    Button(action: onFinishSleep) {
                        Label("Завершить сон", systemImage: "moon")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button(action: onStartSleep) {
                        Label("Начать сон", systemImage: "moon")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button(action: onQuickFeed) {
                        Image(systemName: "drop")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .accessibilityIdentifier("QuickFeedButton")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(accent)
                    .background(FamilyAppStyle.listCardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FamilyAppStyle.cardStroke, lineWidth: 1.5)
                    )
                }
            }
        }
        .padding(24)
        .background(FamilyAppStyle.heroCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FamilyAppStyle.cardStroke, lineWidth: 1.5)
        )
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconBackground: Color
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundColor(Color(.secondaryLabel))
                }
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 185)
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FamilyAppStyle.cardChromeBorder, lineWidth: 1.5)
        )
    }
}

private extension Date {
    var pvlShortTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
    
    var pvlStartLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        if Calendar.current.isDateInToday(self) {
            f.dateFormat = "'сегодня в' HH:mm"
        } else {
            f.setLocalizedDateFormatFromTemplate("d MMM, HH:mm")
        }
        return f.string(from: self)
    }
}

extension Notification.Name {
    static let trackerDataUpdated = Notification.Name("trackerDataUpdated")
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
}
