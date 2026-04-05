import SwiftUI
import Foundation

struct CalendarView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var events: [CalendarEvent] = []
    @State private var showingAddSheet = false
    
    struct CalendarEvent: Identifiable, Codable {
        let id: Int
        let title: String
        let description: String?
        let event_date: String
        let event_type: String
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView("Нет событий", systemImage: "calendar.badge.exclamationmark", description: Text("Добавьте новое событие"))
                } else {
                    List {
                        ForEach(events) { event in
                            EventCard(event: event)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { deleteEvent(id: event.id) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Календарь")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEventView(isPresented: $showingAddSheet, onSave: createEvent)
            }
            .onAppear(perform: loadEvents)
            .refreshable {
                await withCheckedContinuation { continuation in
                    loadEvents()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func loadEvents() {
        guard let token = authManager.token else { return }
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events" : "\(authManager.baseURL)/calendar/events"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { print("Error: \(error)"); return }
            guard let data = data, let list = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return }
            DispatchQueue.main.async { self.events = list }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else { return }
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
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                loadEvents()
            }
        }.resume()
    }
    
    func deleteEvent(id: Int) {
        guard let token = authManager.token else { return }
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events/\(id)" : "\(authManager.baseURL)/calendar/events/\(id)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { loadEvents() }
        }.resume()
    }
    
    func formatDate(_ string: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .short
            f.timeStyle = .short
            return f.string(from: date)
        }
        return string
    }
}

// --- НОВЫЙ КОМПОНЕНТ: КАРТОЧКА СОБЫТИЯ ---
struct EventCard: View {
    let event: CalendarView.CalendarEvent
    
    var accentColor: Color {
        switch event.event_type {
        case "reminder": return .orange
        default: return .blue
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Цветной индикатор слева
            Rectangle()
                .fill(accentColor)
                .frame(width: 6)
                .cornerRadius(3)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let desc = event.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text(formatDate(event.event_date))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    func formatDate(_ string: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        }
        return string
    }
}

struct AddEventView: View {
    @Binding var isPresented: Bool
    let onSave: (String, String, Date, String) -> Void
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var date: Date = Date()
    @State private var type: String = "event"
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $title)
                TextField("Описание", text: $description)
                DatePicker("Дата", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Picker("Тип", selection: $type) {
                    Text("Событие").tag("event")
                    Text("Напоминание").tag("reminder")
                }
            }
            .navigationTitle("Новое событие")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard !title.isEmpty else { return }
                        onSave(title, description, date, type)
                    }
                }
            }
        }
    }
}
