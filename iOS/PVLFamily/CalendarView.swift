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
    
    private var todayEventCount: Int {
        let cal = Calendar.current
        return events.filter { e in
            guard let d = PVLDateParsing.parse(e.event_date) else { return false }
            return cal.isDateInToday(d)
        }.count
    }

    private var groupedEvents: [(title: String, items: [CalendarEvent])] {
        let grouped = Dictionary(grouping: events) { event in
            PVLDateParsing.parse(event.event_date).map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { day in
            let title: String
            if Calendar.current.isDateInToday(day) {
                title = "Сегодня"
            } else if Calendar.current.isDateInYesterday(day) {
                title = "Вчера"
            } else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "ru_RU")
                f.dateFormat = "dd.MM"
                title = f.string(from: day)
            }
            return (title, (grouped[day] ?? []).sorted(by: { $0.event_date > $1.event_date }))
        }
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
                    VStack(alignment: .leading, spacing: 0) {
                        if todayEventCount > 0 {
                            HStack {
                                Text("Сегодня")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(todayEventCount) \(PVLDateParsing.eventWord(todayEventCount))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(FamilyAppStyle.captionMuted)
                            }
                            .padding(16)
                            .pvlPixsoHeroPanel()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                        }
                        List {
                            ForEach(groupedEvents.indices, id: \.self) { sectionIndex in
                                let section = groupedEvents[sectionIndex]
                                let n = section.items.count
                                Section {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, event in
                                        EventCard(event: event, isLastInGroup: index == n - 1)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                            .listRowSeparator(.hidden, edges: .all)
                                            .listRowBackground(
                                                PVLGroupedRowBackground(
                                                    isFirst: index == 0,
                                                    isLast: index == n - 1,
                                                    isSingle: n == 1
                                                )
                                            )
                                            .swipeActions(edge: .trailing) {
                                                Button(role: .destructive) { deleteEvent(id: event.id) } label: {
                                                    Label("Удалить", systemImage: "trash")
                                                }
                                            }
                                    }
                                } header: {
                                    HStack {
                                        Text(section.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(FamilyAppStyle.sectionHeaderForeground)
                                        Spacer()
                                        Text("\(n) \(PVLDateParsing.eventWord(n))")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(FamilyAppStyle.captionMuted)
                                    }
                                    .textCase(nil)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .listRowSpacing(0)
                        .listSectionSpacing(8)
                        .scrollContentBackground(.hidden)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background(FamilyAppStyle.screenBackground)
            .navigationTitle("Дневник")
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

    func parseEventDate(_ string: String) -> Date? {
        PVLDateParsing.parse(string)
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
    var isLastInGroup: Bool = true
    
    var accentColor: Color {
        switch event.event_type {
        case "reminder": return .orange
        default: return FamilyAppStyle.accent
        }
    }

    private var eventIcon: String {
        switch event.event_type {
        case "reminder": return "bell.badge.fill"
        default: return "calendar.badge.plus"
        }
    }

    private var eventTypeTitle: String {
        switch event.event_type {
        case "reminder": return "Напоминание"
        default: return "Событие"
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconBackground)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: eventIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text((event.description?.isEmpty == false ? event.description! : eventTypeTitle))
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(FamilyAppStyle.captionMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeOnly(event.event_date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(shortDate(event.event_date))
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(FamilyAppStyle.captionMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !isLastInGroup {
                Rectangle()
                    .fill(FamilyAppStyle.hairline)
                    .frame(height: 1)
            }
        }
    }

    private var iconBackground: Color {
        event.event_type == "reminder"
            ? FamilyAppStyle.softIconOrange
            : FamilyAppStyle.softIconGreen
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

    func timeOnly(_ string: String) -> String {
        PVLDateParsing.timeHHmm(from: string)
    }

    func shortDate(_ string: String) -> String {
        guard let d = PVLDateParsing.parse(string) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM"
        return f.string(from: d)
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
            .pvlFormScreenStyle()
            .tint(FamilyAppStyle.accent)
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
