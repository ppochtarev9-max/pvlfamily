import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var logs: [BabyLog] = []
    @State private var dailyStats: DailyStats?
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
        let id: Int
        let user_id: Int?
        let event_type: String
        let start_time: String
        let end_time: String?
        let duration_minutes: Int?
        let note: String?
        let is_active: Bool
    }
    
    struct DailyStats: Codable {
        let total_sleep_minutes: Int
        let total_wake_minutes: Int
        let sessions_count: Int
    }
    
    var sleepTimeText: String { formatMinutes(dailyStats?.total_sleep_minutes ?? 0) }
    var wakeTimeText: String { formatMinutes(dailyStats?.total_wake_minutes ?? 0) }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // === ШАПКА С АНАЛИТИКОЙ ===
                ScrollView {
                    VStack(spacing: 16) {
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
                            TrackerStatsView()
                        }
                        
                        Divider().padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground))
                }
                .frame(height: 220)
                
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
                        .onChange(of: selectedDate) { _, newValue in
                            showDatePicker = false
                            loadDailyStats(for: newValue, from: logs)
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
                        loadLogs()
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
            }
            .refreshable {
                loadLogs()
            }
        }
    }
    
    func loadLogs() {
        guard let token = authManager.token else {
            errorMessage = "Нет авторизации"; showErrorAlert = true; return
        }
        isLoading = true
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription; showErrorAlert = true; return
                }
                
                guard let data = data else {
                    errorMessage = "Пустой ответ"; showErrorAlert = true; return
                }
                
                do {
                    let list = try JSONDecoder().decode([BabyLog].self, from: data)
                    print("✅ Загружено записей: \(list.count)")
                    self.logs = list
                    // Пересчет для текущей даты после загрузки
                    self.loadDailyStats(for: self.selectedDate, from: list)
                } catch {
                    errorMessage = "Ошибка данных: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func loadDailyStats(for date: Date, from allLogs: [BabyLog]) {
        let calendar = Calendar.current
        let now = Date()
        let isToday = calendar.isDate(date, inSameDayAs: now)
        
        var totalSleep = 0
        var count = 0
        
        for log in allLogs where log.event_type == "sleep" {
            guard let logDate = parseDate(log.start_time) else { continue }
            
            if calendar.isDate(logDate, inSameDayAs: date) {
                if let dur = log.duration_minutes {
                    totalSleep += dur
                    count += 1
                } else if log.is_active && isToday {
                    // Активный сон только если смотрим "Сегодня"
                    let dur = Int(now.timeIntervalSince(logDate) / 60)
                    if dur > 0 {
                        totalSleep += dur
                        count += 1
                    }
                }
            }
        }
        
        var totalWake = 0
        if isToday {
            // Сегодня: (Минут с начала дня) - Сон
            if let startOfDay = calendar.startOfDay(for: now) as Date? {
                let passed = Int(now.timeIntervalSince(startOfDay) / 60)
                totalWake = max(0, passed - totalSleep)
            }
        } else {
            // Прошлые дни: 24 часа (1440 мин) - Сон
            // Или можно сделать 0, если день неполный, но логичнее показать остаток от суток
            totalWake = max(0, 1440 - totalSleep)
        }
        
        print("📊 Статистика за \(formatDateShort(date)): Сон \(totalSleep) мин, Бодрствование \(totalWake) мин")
        
        DispatchQueue.main.async {
            self.dailyStats = DailyStats(
                total_sleep_minutes: totalSleep,
                total_wake_minutes: totalWake,
                sessions_count: count
            )
        }
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
                if let error = error {
                    errorMessage = error.localizedDescription; showErrorAlert = true; return
                }
                guard let httpResponse = response as? HTTPURLResponse else { return }
                if !(200...299).contains(httpResponse.statusCode) {
                    errorMessage = "Ошибка сервера (\(httpResponse.statusCode))"; showErrorAlert = true; return
                }
                showingAddSheet = false; selectedLog = nil
                loadLogs()
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
                loadLogs()
                NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
            }
        }.resume()
    }
    
    func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60; let m = mins % 60
        return String(format: "%02d:%02d", h, m)
    }
    
    func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }
    
    func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: string)
    }
}

// LogCard - полностью восстановлен стиль как в TransactionCard
struct LogCard: View {
    let log: TrackerView.BabyLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Верхняя часть: Название и длительность
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.event_type == "sleep" ? "Сон" : "Кормление")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Длительность справа сверху
                if let dur = log.duration_minutes, dur > 0 {
                    Text("\(dur) мин")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(log.event_type == "sleep" ? .purple : .orange)
                } else if log.is_active {
                    Text("Идет...")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
            
            Divider().background(Color.gray.opacity(0.2))
            
            // Нижняя часть: Время начала и конца (как в транзакциях)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Начало").font(.caption2).foregroundColor(.secondary).textCase(.uppercase)
                    Text(formatDateTime(log.start_time)).font(.title3).fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 1) {
                    if let end = log.end_time {
                        Text("Окончание").font(.caption2).foregroundColor(.secondary).textCase(.uppercase)
                        Text(formatDateTime(end)).font(.title3)
                    } else {
                        Text("Активно").font(.caption2).foregroundColor(.orange).textCase(.uppercase)
                        Text("—").font(.title3)
                    }
                }
            }
            .foregroundColor(.gray)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((log.event_type == "sleep" ? Color.purple : Color.orange).opacity(0.15), lineWidth: 1)
        )
    }
    
    // Форматирование даты как в транзакциях (ДД.ММ.ГГ, ЧЧ:ММ)
    func formatDateTime(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .short
            return f.string(from: d)
        }
        
        // Fallback для старых форматов
        if let tIndex = string.firstIndex(of: "T") {
            let datePart = String(string[..<tIndex])
            let timePart = String(string[string.index(after: tIndex)...]).prefix(5)
            let parts = datePart.split(separator: "-")
            if parts.count == 3 {
                return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2))), \(timePart)"
            }
            return datePart
        }
        return string
    }
}
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
        .onAppear { performQuickAction() }
    }
    
    func performQuickAction() {
        guard let token = authManager.token else { onError("Не авторизован"); return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let iso = ISO8601DateFormatter()
        let now = Date()
        let body: [String: Any] = ["event_type": eventType, "start_time": iso.string(from: now), "end_time": iso.string(from: now), "note": "Быстрая запись"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { onError(error.localizedDescription); return }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { onError("Ошибка сервера"); return }
                isProcessing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
            }
        }.resume()
    }
}
