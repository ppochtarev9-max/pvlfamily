import SwiftUI
import Foundation

struct CalendarView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var events: [CalendarEvent] = []
    
    // Состояния UI
    @State private var showingAddSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isSaving = false
    
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
                if isLoading && events.isEmpty {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, events.isEmpty {
                    ContentUnavailableView(
                        "Ошибка загрузки",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(error)
                    )
                } else if events.isEmpty {
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
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .opacity(isSaving ? 0.5 : 1.0)
                            .disabled(isSaving)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEventView(
                    isPresented: $showingAddSheet,
                    onSave: createEvent,
                    isSaving: isSaving
                )
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
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
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events" : "\(authManager.baseURL)/calendar/events"
        var req = URLRequest(url: URL(string: urlStr)!)
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
                    let list = try JSONDecoder().decode([CalendarEvent].self, from: data)
                    self.events = list
                } catch {
                    errorMessage = "Ошибка обработки данных: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func createEvent(title: String, desc: String, date: Date, type: String) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        errorMessage = nil
        
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
                isSaving = false
                
                if let error = error {
                    errorMessage = "Ошибка сохранения: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при создании события"
                    showErrorAlert = true
                    return
                }
                
                showingAddSheet = false
                loadEvents()
            }
        }.resume()
    }
    
    func deleteEvent(id: Int) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        // Оптимистичное удаление из UI
        let originalEvents = events
        events.removeAll { $0.id == id }
        
        let urlStr = authManager.baseURL.hasSuffix("/") ? "\(authManager.baseURL)calendar/events/\(id)" : "\(authManager.baseURL)/calendar/events/\(id)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    // Откат изменений при ошибке
                    self.events = originalEvents
                    errorMessage = "Ошибка удаления: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    // Откат изменений при ошибке
                    self.events = originalEvents
                    errorMessage = "Ошибка сервера при удалении"
                    showErrorAlert = true
                    return
                }
                
                loadEvents()
            }
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

// --- КОМПОНЕНТ: КАРТОЧКА СОБЫТИЯ ---
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
    let isSaving: Bool
    
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard !title.isEmpty else { return }
                        onSave(title, description, date, type)
                    }
                    .disabled(isSaving)
                    .overlay(
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            }
                        }
                    )
                }
            }
        }
    }
}
