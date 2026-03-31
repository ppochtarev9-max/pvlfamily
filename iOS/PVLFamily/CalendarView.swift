import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var events: [Event] = []
    @State private var showingAddSheet = false
    @State private var newTitle = ""
    @State private var newDate = Date()
    
    struct Event: Identifiable, Codable {
        let id: Int
        let title: String
        let event_date: String
        let event_type: String
    }
    
    var body: some View {
        NavigationView {
            Group {
                if events.isEmpty {
                    Text("Нет событий")
                        .foregroundColor(.gray)
                } else {
                    List {
                        ForEach(events) { e in
                            VStack(alignment: .leading) {
                                Text(e.title).font(.headline)
                                Text(formatDate(e.event_date))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Календарь")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddSheet = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addEventSheet()
            }
            .onAppear(perform: loadEvents)
        }
    }
    
    func formatDate(_ string: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: string) else { return string }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func loadEvents() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/calendar/events")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let list = try? JSONDecoder().decode([Event].self, from: data) else { return }
            DispatchQueue.main.async { events = list }
        }.resume()
    }
    
    func addEventSheet() -> some View {
        NavigationView {
            Form {
                TextField("Название события", text: $newTitle)
                DatePicker("Дата", selection: $newDate, displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Новое событие")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { showingAddSheet = false } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { saveEvent() }
                }
            }
        }
    }
    
    func saveEvent() {
        guard !newTitle.isEmpty, let token = authManager.token else { return }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/calendar/events")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = ["title": newTitle, "event_date": formatter.string(from: newDate), "event_type": "general"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                newTitle = ""
                loadEvents()
            }
        }.resume()
    }
}
