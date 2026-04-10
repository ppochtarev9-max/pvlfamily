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
                            LogCard(log: log)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedLog = log
                                    showingAddSheet = true
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteLog(id: log.id)
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        selectedLog = log
                                        showingAddSheet = true
                                    } label: {
                                        Label("Изменить", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("История трекера")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: TrackerStatsView()) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        selectedLog = nil
                        preselectedType = nil
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
                    QuickActionHandler(
                        eventType: type,
                        authManager: authManager,
                        onComplete: {
                            showingAddSheet = false
                            preselectedType = nil
                            loadLogs()
                            NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
                        },
                        onError: { err in
                            errorMessage = err
                            showErrorAlert = true
                            showingAddSheet = false
                            preselectedType = nil
                        }
                    )
                } else {
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
        
        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "event_type": type,
            "start_time": isoFormatter.string(from: startTime)
        ]
        if let end = endTime { body["end_time"] = isoFormatter.string(from: end) }
        if !note.isEmpty { body["note"] = note }
        
        var req: URLRequest
        let urlString: String
        
        if let log = selectedLog {
            urlString = "\(authManager.baseURL)/tracker/logs/\(log.id)"
            req = URLRequest(url: URL(string: urlString)!)
            req.httpMethod = "PUT"
        } else {
            urlString = "\(authManager.baseURL)/tracker/logs"
            req = URLRequest(url: URL(string: urlString)!)
            req.httpMethod = "POST"
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера"
                    showErrorAlert = true
                    return
                }
                
                showingAddSheet = false
                selectedLog = nil
                loadLogs()
                NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
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
                NotificationCenter.default.post(name: .trackerDataUpdated, object: nil)
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

struct LogCard: View {
    let log: TrackerView.BabyLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleForType(log.event_type)).font(.headline).fontWeight(.semibold).lineLimit(1)
                    if let note = log.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                if let dur = log.duration_minutes, dur > 0 {
                    Text("\(dur) мин")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(colorForType(log.event_type))
                } else if log.is_active {
                    Text("Идет...")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
            
            Divider().background(Color.gray.opacity(0.2))
            
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
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(colorForType(log.event_type).opacity(0.15), lineWidth: 1))
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
            if parts.count == 3 { return "\(parts[2]).\(parts[1]).\(String(parts[0].suffix(2))), \(timePart)" }
            return datePart
        }
        return string
    }
}
