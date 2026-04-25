import SwiftUI
import Charts

struct TrackerStatsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDays = 7
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка статистики...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let stats = stats {
                    ScrollView {
                        VStack(spacing: 24) {
                            Picker("Период", selection: $selectedDays) {
                                Text("7 дней").tag(7)
                                Text("30 дней").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .tint(FamilyAppStyle.accent)
                            .padding(.horizontal)
                            .onChange(of: selectedDays) { _, newValue in
                                loadStats(days: newValue)
                            }
                            
                            VStack(spacing: 12) {
                                HStack {
                                    StatCard(
                                        title: "Всего сна",
                                        value: formatHours(stats.total_sleep_minutes),
                                        icon: "moon.fill",
                                        color: FamilyAppStyle.accent
                                    )
                                    StatCard(
                                        title: "Средний сон",
                                        value: formatHours(stats.average_sleep_minutes),
                                        icon: "clock.fill",
                                        color: FamilyAppStyle.accent
                                    )
                                }
                                HStack {
                                    StatCard(
                                        title: "Кол-во снов",
                                        value: "\(stats.total_sessions)",
                                        icon: "list.bullet",
                                        color: .orange
                                    )
                                    StatCard(
                                        title: "Дней в выборке",
                                        value: "\(stats.period_days)",
                                        icon: "calendar",
                                        color: Color(.secondaryLabel)
                                    )
                                }
                            }
                            .padding(.horizontal)
                            
                            Text("Динамика по дням")
                                .font(.system(size: 14, weight: .semibold))
                                .tracking(0.8)
                                .foregroundColor(Color(.secondaryLabel))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            if #available(iOS 17.0, *) {
                                Chart(stats.daily_breakdown, id: \.date) { item in
                                    BarMark(
                                        x: .value("Дата", formatDateShort(item.date)),
                                        y: .value("Минуты", item.sleep_minutes)
                                    )
                                    .foregroundStyle(FamilyAppStyle.accent.gradient)
                                    .cornerRadius(4)
                                    .annotation(position: .top) {
                                        Text(formatHours(item.sleep_minutes))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(height: 200)
                                .padding(.horizontal)
                            } else {
                                List(stats.daily_breakdown) { item in
                                    HStack {
                                        Text(formatDateShort(item.date))
                                        Spacer()
                                        Text(formatHours(item.sleep_minutes))
                                            .fontWeight(.bold)
                                    }
                                }
                                .frame(height: 300)
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.vertical)
                    }
                } else {
                    ContentUnavailableView("Нет данных", systemImage: "chart.bar.xaxis", description: Text("Попробуйте изменить период"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FamilyAppStyle.screenBackground)
            .navigationTitle("Статистика сна")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(FamilyAppStyle.accent)
                }
            }
            .onAppear {
                loadStats(days: selectedDays)
            }
        }
    }
    
    func loadStats(days: Int) {
        isLoading = true
        errorMessage = nil
        
        guard let token = authManager.token else {
            errorMessage = "Не авторизован"
            isLoading = false
            return
        }
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/tracker/stats?days=\(days)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера"
                    return
                }
                
                guard let data = data else {
                    errorMessage = "Нет данных"
                    return
                }
                
                do {
                    self.stats = try JSONDecoder().decode(TrackerStats.self, from: data)
                } catch {
                    self.errorMessage = "Ошибка парсинга: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)ч \(m)м" }
        return "\(m)м"
    }
    
    func formatDateShort(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: isoString) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "dd.MM"
            outFormatter.locale = Locale(identifier: "ru_RU")
            return outFormatter.string(from: date)
        }
        return isoString
    }
}

struct TrackerStats: Codable {
    let period_days: Int
    let total_sleep_minutes: Int
    let total_sessions: Int
    let average_sleep_minutes: Int
    let daily_breakdown: [DailyStat]
}

struct DailyStat: Codable, Identifiable {
    let date: String
    let sleep_minutes: Int
    let sessions_count: Int
    var id: String { date }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Text(value).font(.title2).fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
    }
}
