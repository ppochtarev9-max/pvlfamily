import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var logs: [BabyLog] = []
    @State private var dailyStats: DailyStats? // Данные для шапки
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // Фильтры и навигация
    @State private var selectedDate: Date = Date()
    @State private var showDatePicker = false
    @State private var navigateToStats = false
    
    // Форма
    @State private var showingAddSheet = false
    @State private var selectedLog: BabyLog? = nil
    @State private var preselectedType: String? = nil
    
    struct BabyLog: Identifiable, Codable {
        let id: Int; let user_id: Int?; let event_type: String
        let start_time: String; let end_time: String?
        let duration_minutes: Int?; let note: String?; let is_active: Bool
    }
    
    struct DailyStats: Codable {
        let total_sleep_minutes: Int
        let total_wake_minutes: Int // Вычисляем сами или просим с бека
        let sessions_count: Int
    }
    
    // Вычисляемые свойства для шапки
    var sleepTimeText: String { formatMinutes(dailyStats?.total_sleep_minutes ?? 0) }
    var wakeTimeText: String { formatMinutes(calculateWakeTime()) }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // === ШАПКА С АНАЛИТИКОЙ ===
                ScrollView {
                    VStack(spacing: 16) {
                        // Карточка статистики
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Сон").font(.caption).foregroundColor(.secondary)
                                    Text(sleepTimeText).font(.title2).fontWeight(.bold).foregroundColor(.purple)
                                }
                                Divider().frame(height: 30)
                                VStack(alignment: .leading) {
                                    Text("Бодрствование").font(.caption).foregroundColor(.secondary)
                                    Text(wakeTimeText).font(.title2).fontWeight(.bold).foregroundColor(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            Text("\(dailyStats?.sessions_count ?? 0) снов за день")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(20)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal)
                        
                        // Кнопка Детализация (Статистика)
                        Button(action: { navigateToStats = true }) {
                            Text("Аналитика")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .navigationDestination(isPresented: $navigateToStats) {
                            TrackerStatsView() // Твой существующий экран
                        }
                        
                        Divider().padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground))
                }
                .frame(height: 220) // Фиксированная высота шапки
                
                // === СПИСОК ===
                Group {
                    if isLoading && logs.isEmpty {
                        ProgressView("Загрузка...")
                    } else if logs.isEmpty {
                        ContentUnavailableView("Нет записей", systemImage: "clock.badge.exclamationmark", description: Text("Нажмите +, чтобы добавить"))
                    } else {
                        List {
                            ForEach(logs.sorted(by: { $0.start_time > $1.start_time })) { log in
                                LogCard(log: log)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedLog = log
                                        showingAddSheet = true
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { deleteLog(id: log.id) } label: { Label("Удалить", systemImage: "trash") }
                                        Button { selectedLog = log; showingAddSheet = true } label: { Label("Изменить", systemImage: "pencil") }.tint(.blue)
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("Трекер за ")
                            .font(.system(size: 18, weight: .semibold))
                        Button(action: { showDatePicker = true }) {
                            HStack(spacing: 2) {
                                Text(formatDateShort(selectedDate)).fontWeight(.medium)
                                Image(systemName: "calendar").font(.caption)
                            }
                            .foregroundColor(.purple)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        selectedLog = nil; preselectedType = nil; showingAddSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                VStack(spacing: 20) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: selectedDate) { _, _ in
                            showDatePicker = false
                            loadLogs() // Перезагрузка под дату
                            loadDailyStats() // Загрузка статистики
                        }
                    Button("Закрыть") { showDatePicker = false }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 20)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddSheet) {
                if let type = preselectedType {
                    QuickActionHandler(eventType: type, authManager: authManager, onComplete: {
                        showingAddSheet = false; preselectedType = nil
                        loadLogs(); loadDailyStats()
                        NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
                    }, onError: { err in errorMessage = err; showErrorAlert = true })
                } else {
                    TrackerFormView(isPresented: $showingAddSheet, existingLog: selectedLog, onSave: saveLog, onDelete: deleteLog)
                }
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Ошибка") }
            .onAppear {
                loadLogs()
                loadDailyStats()
            }
            .refreshable {
                loadLogs()
                loadDailyStats()
            }
        }
    }
    
    // --- ЛОГИКА ---
    
    func loadLogs() {
        guard let token = authManager.token else { return }
        isLoading = true
        // В реальном проекте нужно передавать дату на бэк, пока фильтруем локально для примера
        // Но лучше сделать параметр в запросе
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let data = data, let list = try? JSONDecoder().decode([BabyLog].self, from: data) else { return }
                
                // Фильтрация по дате (локально, если бэк не умеет)
                let calendar = Calendar.current
                self.logs = list.filter { log in
                    guard let d = parseDate(log.start_time) else { return false }
                    return calendar.isDate(d, inSameDayAs: selectedDate)
                }
            }
        }.resume()
    }
    
    func loadDailyStats() {
        // Здесь нужен запрос к новому эндпоинту или расчет локально
        // Для примера рассчитаем локально из загруженных логов
        var totalSleep = 0
        var count = 0
        for log in logs where log.event_type == "sleep" {
            if let dur = log.duration_minutes {
                totalSleep += dur
                count += 1
            }
        }
        // Бодрствование сложно посчитать точно без знания времени подъема/укладывания родителя
        // Пока поставим заглушку или сумму длительностей бодрствования между снами
        dailyStats = DailyStats(total_sleep_minutes: totalSleep, total_wake_minutes: 0, sessions_count: count)
    }
    
    func calculateWakeTime() -> Int {
        // Простая эвристика: сумма длительностей кормлений + (если есть данные о бодрствовании)
        var totalWake = 0
        for log in logs where log.event_type == "feed" {
            if let dur = log.duration_minutes { totalWake += dur }
        }
        return totalWake
    }
    
    func saveLog(type: String, startTime: Date, endTime: Date?, note: String) {
        guard let token = authManager.token else { return }
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["event_type": type, "start_time": iso.string(from: startTime)]
        if let end = endTime { body["end_time"] = iso.string(from: end) }
        if !note.isEmpty { body["note"] = note }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.httpMethod = selectedLog != nil ? "PUT" : "POST"
        if let log = selectedLog { req.url = URL(string: "\(authManager.baseURL)/tracker/logs/\(log.id)")! }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingAddSheet = false; selectedLog = nil
                loadLogs(); loadDailyStats()
                NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
            }
        }.resume()
    }
    
    func deleteLog(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { errorMessage = error.localizedDescription; showErrorAlert = true; return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
                showingAddSheet = false; selectedLog = nil
                loadLogs(); loadDailyStats()
                NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
            }
        }.resume()
    }
    
    // Helpers
    func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return String(format: "%02d:%02d", h, m)
    }
    func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }
    func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }
}

// LogCard (оставь тот же, что был, или используй упрощенный)
struct LogCard: View {
    let log: TrackerView.BabyLog
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(log.event_type == "sleep" ? "Сон" : "Кормление").font(.headline).fontWeight(.semibold)
                Spacer()
                if let dur = log.duration_minutes, dur > 0 {
                    Text("\(dur) мин").font(.title3).fontWeight(.bold).foregroundColor(log.event_type == "sleep" ? .purple : .orange)
                }
            }
            Divider()
            HStack {
                Text(formatDateTime(log.start_time)).font(.caption).foregroundColor(.secondary)
                Spacer()
                if let end = log.end_time {
                    Text(formatDateTime(end)).font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Идет...").font(.caption).foregroundColor(.orange).fontWeight(.bold)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
    func formatDateTime(_ string: String) -> String {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) {
            let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateStyle = .short; f.timeStyle = .short
            return f.string(from: d)
        }
        return string
    }
}
// --- Вспомогательный виджет для быстрого действия ---
struct QuickActionHandler: View {
    let eventType: String
    let authManager: AuthManager
    let onComplete: () -> Void
    let onError: (String) -> Void
    
    @State private var isProcessing = true
    
    var body: some View {
        VStack(spacing: 20) {
            if isProcessing {
                ProgressView("Запись события...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
            } else {
                Text("Готово")
            }
        }
        .frame(width: 200, height: 200)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .onAppear {
            performQuickAction()
        }
    }
    
    func performQuickAction() {
        guard let token = authManager.token else {
            onError("Не авторизован")
            return
        }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        let now = Date()
        let body: [String: Any] = [
            "event_type": eventType,
            "start_time": isoFormatter.string(from: now),
            "end_time": isoFormatter.string(from: now),
            "note": "Быстрая запись"
        ]
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    onError(error.localizedDescription)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    onError("Ошибка сервера")
                    return
                }
                
                isProcessing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }.resume()
    }
}
