import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var logs: [BabyLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // Управление формой
    @State private var showingAddSheet = false
    @State private var selectedLog: BabyLog? = nil
    @State private var preselectedType: String? = nil // Для быстрого создания
    
    struct BabyLog: Identifiable, Codable {
        let id: Int
        let user_id: Int?
        let event_type: String
        let start_time: String
        let end_time: String?
        let duration_minutes: Int?
        let note: String?
        let is_active: Bool // Новое поле с бэка
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && logs.isEmpty {
                    ProgressView("Загрузка истории...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, logs.isEmpty {
                    ContentUnavailableView(
                        "Ошибка загрузки",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(error)
                    )
                } else if logs.isEmpty {
                    ContentUnavailableView(
                        "История пуста",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("Нажмите +, чтобы добавить событие")
                    )
                } else {
                    List {
                        ForEach(logs.sorted(by: { $0.start_time > $1.start_time })) { log in
                            LogCard(log: log, onTap: {
                                selectedLog = log
                                showingAddSheet = true
                            })
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("История трекера")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        selectedLog = nil
                        preselectedType = nil // Открываем пустую форму выбора
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                if let type = preselectedType {
                    // Быстрое действие (Кормление) - отдельный обработчик
                    QuickActionHandler(
                        eventType: type,
                        authManager: authManager,
                        onComplete: {
                            showingAddSheet = false
                            preselectedType = nil
                            loadLogs()
                        },
                        onError: { err in
                            errorMessage = err
                            showErrorAlert = true
                            showingAddSheet = false
                            preselectedType = nil
                        }
                    )
                } else {
                    // Обычная форма (Сон или Редактирование)
                    // Убедись, что TrackerFormView принимает именно эти параметры
                    TrackerFormView(
                        isPresented: $showingAddSheet,
                        existingLog: selectedLog,
                        onSave: saveLog,
                        onDelete: deleteLog
                    )
                }
            }
        
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .onAppear(perform: loadLogs)
            .refreshable {
                await withCheckedContinuation { continuation in
                    loadLogs()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func loadLogs() {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    errorMessage = "Неверный ответ сервера"
                    showErrorAlert = true
                    return
                }
                
                if !(200...299).contains(httpResponse.statusCode) {
                    errorMessage = "Ошибка сервера (код \(httpResponse.statusCode))"
                    showErrorAlert = true
                    return
                }
                
                guard let data = data else {
                    errorMessage = "Пустой ответ от сервера"
                    showErrorAlert = true
                    return
                }
                
                do {
                    let list = try JSONDecoder().decode([BabyLog].self, from: data)
                    self.logs = list
                } catch {
                    errorMessage = "Ошибка обработки данных: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func saveLog(type: String, startTime: Date, endTime: Date?, note: String) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "event_type": type,
            "start_time": isoFormatter.string(from: startTime)
        ]
        if let end = endTime { body["end_time"] = isoFormatter.string(from: end) }
        if !note.isEmpty { body["note"] = note }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Ошибка сохранения: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при сохранении"
                    showErrorAlert = true
                    return
                }
                
                showingAddSheet = false
                selectedLog = nil
                loadLogs()
            }
        }.resume()
    }
    
    func deleteLog(id: Int) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        let originalLogs = logs
        logs.removeAll { $0.id == id }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.logs = originalLogs
                    errorMessage = "Ошибка удаления: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.logs = originalLogs
                    errorMessage = "Ошибка сервера при удалении"
                    showErrorAlert = true
                    return
                }
                
                showingAddSheet = false
                selectedLog = nil
                loadLogs()
            }
        }.resume()
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
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs/quick-feed")!)
        // Если вдруг захотим быстро создать что-то еще, можно сделать универсальный эндпоинт
        // Пока используем общий POST, но без формы
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        let now = Date()
        let body: [String: Any] = [
            "event_type": eventType,
            "start_time": isoFormatter.string(from: now),
            "end_time": isoFormatter.string(from: now), // Кормление мгновенное
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

struct LogCard: View {
    let log: TrackerView.BabyLog
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(colorForType(log.event_type).opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: iconForType(log.event_type)).font(.title3).foregroundColor(colorForType(log.event_type))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleForType(log.event_type)).font(.headline).foregroundColor(.primary)
                    HStack(spacing: 8) {
                        Text(formatTime(log.start_time)).font(.caption).foregroundColor(.secondary)
                        if let end = log.end_time {
                            Text("•").foregroundColor(.secondary)
                            Text(formatTime(end)).font(.caption).foregroundColor(.secondary)
                            if let dur = log.duration_minutes {
                                Text("• \(dur) мин").font(.caption).fontWeight(.medium).foregroundColor(.blue)
                            }
                        } else {
                            Text("• Идет...").font(.caption).foregroundColor(.orange).fontWeight(.medium)
                        }
                    }
                    if let note = log.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func iconForType(_ type: String) -> String {
        switch type {
        case "sleep": return "moon.fill"
        case "feed": return "fork.knife"
        default: return "clock.fill"
        }
    }
    
    func colorForType(_ type: String) -> Color {
        switch type {
        case "sleep": return .purple
        case "feed": return .orange
        default: return .gray
        }
    }
    
    func titleForType(_ type: String) -> String {
        switch type {
        case "sleep": return "Сон"
        case "feed": return "Кормление"
        default: return "Событие"
        }
    }
    
    func formatTime(_ string: String) -> String {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.timeStyle = .short
            return f.string(from: d)
        }
        return string
    }
}
