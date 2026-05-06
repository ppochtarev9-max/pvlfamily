import SwiftUI
import Charts

struct TrackerStatsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss

    /// Если `false` — вложен в навигацию с родителя (`TrackerAnalyticsHubView`).
    var embedInNavigationStack: Bool = true

    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDays = 7
    @State private var selectedDayLabel: String?

    var body: some View {
        let page = Group {
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
                                    value: AnalyticsFormatters.sleepDurationWithMinutesHint(stats.total_sleep_minutes),
                                    icon: "moon.fill",
                                    color: FamilyAppStyle.accent
                                )
                                StatCard(
                                    title: "Средний сон",
                                    value: AnalyticsFormatters.sleepDurationWithMinutesHint(stats.average_sleep_minutes),
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
                            let ordered = stats.daily_breakdown.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
                            let points: [(dayLabel: String, minutes: Int)] = ordered.map { (AnalyticsFormatters.dayLabelDDMM(fromISO: $0.date), $0.sleep_minutes) }
                            let minutesByDay = Dictionary(uniqueKeysWithValues: points.map { ($0.dayLabel, $0.minutes) })
                            Chart {
                                ForEach(points, id: \.dayLabel) { p in
                                    BarMark(
                                        x: .value("Дата", p.dayLabel),
                                        y: .value("Минуты", p.minutes)
                                    )
                                    .foregroundStyle(FamilyAppStyle.accent.gradient)
                                    .cornerRadius(4)
                                }
                                if let selectedDayLabel, let v = minutesByDay[selectedDayLabel] {
                                    RuleMark(x: .value("Дата", selectedDayLabel))
                                        .foregroundStyle(.secondary.opacity(0.35))
                                        .annotation(position: .top, alignment: .leading) {
                                            TrackerChartCallout(
                                                title: selectedDayLabel,
                                                rows: [("Сон", AnalyticsFormatters.sleepDurationWithMinutesHint(v))]
                                            )
                                        }
                                }
                            }
                            .chartXSelection(value: $selectedDayLabel)
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(.clear)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let origin = geo[proxy.plotAreaFrame].origin
                                                    let x = value.location.x - origin.x
                                                    if let label: String = proxy.value(atX: x) {
                                                        selectedDayLabel = label
                                                    }
                                                }
                                        )
                                }
                            }
                            .frame(height: 200)
                            .padding(.horizontal)
                        } else {
                            List(stats.daily_breakdown) { item in
                                HStack {
                                    Text(AnalyticsFormatters.dayLabelDDMM(fromISO: item.date))
                                    Spacer()
                                    Text(AnalyticsFormatters.sleepDurationWithMinutesHint(item.sleep_minutes))
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedInNavigationStack {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(FamilyAppStyle.accent)
                }
            }
        }
        .onAppear {
            loadStats(days: selectedDays)
        }

        if embedInNavigationStack {
            NavigationStack { page }
        } else {
            page
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
    
    // форматирование вынесено в AnalyticsFormatters
}

struct TrackerStats: Codable {
    let period_days: Int
    let total_sleep_minutes: Int
    let total_sessions: Int
    let average_sleep_minutes: Int
    let total_day_sleep_minutes: Int?
    let total_night_sleep_minutes: Int?
    let total_day_sessions: Int?
    let total_night_sessions: Int?
    let daily_breakdown: [DailyStat]
}

struct DailyStat: Codable, Identifiable {
    let date: String
    let sleep_minutes: Int
    let sessions_count: Int
    let day_sleep_minutes: Int?
    let night_sleep_minutes: Int?
    let day_sessions_count: Int?
    let night_sessions_count: Int?
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
