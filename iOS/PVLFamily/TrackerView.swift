import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var logs: [BabyLog] = []
    @State private var showingAddSheet = false
    @State private var selectedLog: BabyLog? = nil
    
    struct BabyLog: Identifiable, Codable {
        let id: Int
        let user_id: Int?
        let event_type: String
        let start_time: String
        let end_time: String?
        let duration_minutes: Int?
        let note: String?
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "Записей пока нет",
                        systemImage: "heart.fill",
                        description: Text("Нажмите +, чтобы добавить событие")
                    )
                } else {
                    List {
                        ForEach(logs.sorted(by: { $0.start_time > $1.start_time })) { log in
                            LogCard(log: log, onTap: { selectedLog = log; showingAddSheet = true })
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Трекер")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                TrackerFormView(
                    isPresented: $showingAddSheet,
                    existingLog: selectedLog,
                    onSave: saveLog,
                    onDelete: deleteLog
                )
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
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { print("Error loading logs: \(error)"); return }
            guard let data = data, let list = try? JSONDecoder().decode([BabyLog].self, from: data) else { return }
            DispatchQueue.main.async { self.logs = list }
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
        if let end = endTime { body["end_time"] = isoFormatter.string(from: end) }
        if !note.isEmpty { body["note"] = note }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                selectedLog = nil
                loadLogs()
            }
        }.resume()
    }
    
    func deleteLog(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/logs/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                selectedLog = nil
                loadLogs()
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
                            Text("...в процессе").font(.caption).foregroundColor(.orange).fontWeight(.medium)
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
        case "diaper": return "drop.fill"
        case "play": return "heart.fill"
        default: return "clock.fill"
        }
    }
    
    func colorForType(_ type: String) -> Color {
        switch type {
        case "sleep": return .purple
        case "feed": return .orange
        case "diaper": return .blue
        case "play": return .pink
        default: return .gray
        }
    }
    
    func titleForType(_ type: String) -> String {
        switch type {
        case "sleep": return "Сон"
        case "feed": return "Кормление"
        case "diaper": return "Смена памперса"
        case "play": return "Игра / Бодрствование"
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
