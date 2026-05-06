import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Данные
    @State private var logs: [BabyLog] = []
    @State private var dailyStats: DailyStats?
    @State private var isLoading = false
    @State private var hasMoreLogs = false
    @State private var isLoadingMoreLogs = false
    @State private var nextLogsCursor: (startISO: String, id: Int)? = nil
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    /// Кэш секций дней — не пересчитывать O(n) на каждый кадр SwiftUI.
    @State private var logDaySections: [LogDaySection] = []
    @State private var didRunInitialTrackerLoad = false
    @State private var lastLogsLoadedAt: Date? = nil
    
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

    fileprivate struct LogDaySection: Identifiable {
        let id: String
        let day: Date
        let title: String
        let items: [BabyLog]
    }
    
    fileprivate struct LogsListPage: Codable {
        let items: [BabyLog]
        let has_more: Bool
        let total: Int
    }
    
    private var sleepColumnTitle: String {
        Calendar.current.isDateInToday(selectedDate) ? "СОН СЕГОДНЯ" : "СОН"
    }

    /// Сон за выбранные сутки — «9ч 42м», как в Pixso.
    private var sleepDurationHero: String {
        formatSleepDurationPixso(dailyStats?.total_sleep_minutes ?? 0)
    }

    private var episodesHero: String {
        "\(dailyStats?.sessions_count ?? 0)"
    }

    /// Время первого пробуждения в этот день (ранний `end_time` сна), «08:14».
    private var firstWakeClockHero: String {
        guard let d = firstWakeTime(on: selectedDate, logs: logs) else { return "—" }
        return Self.hhmmFormatterRU.string(from: d)
    }
    
    private func refreshLogDaySections(from allLogs: [BabyLog]) {
        let cal = Calendar.current
        // keyset пагинация от API уже даёт порядок по времени, но на всякий случай держим стабильную сортировку.
        let sortedLogs = allLogs.sorted(by: { $0.start_time > $1.start_time })
        let grouped = Dictionary(grouping: sortedLogs) { log in
            parseDate(log.start_time).map { cal.startOfDay(for: $0) } ?? .distantPast
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        logDaySections = sortedKeys.map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Сегодня" }
            else if cal.isDateInYesterday(day) { title = "Вчера" }
            else { title = Self.dayTitleFormatterRU.string(from: day) }
            return LogDaySection(
                id: "\(day.timeIntervalSince1970)",
                day: day,
                title: title,
                items: grouped[day] ?? []
            )
        }
    }

    @ViewBuilder
    private func trackerHeroColumn(title: String, systemImage: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(1)
                .multilineTextAlignment(.center)
                .foregroundColor(FamilyAppStyle.captionMuted)
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FamilyAppStyle.pixsoInk)
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .kerning(-0.5)
                    .foregroundColor(FamilyAppStyle.pixsoInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func formatSleepDurationPixso(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        if h > 0, m > 0 { return "\(h)ч \(m)м" }
        if h > 0 { return "\(h)ч" }
        return "\(m)м"
    }

    /// Раннее окончание сна в этот день (по макету — «время пробуждения»).
    private func firstWakeTime(on day: Date, logs: [BabyLog]) -> Date? {
        let cal = Calendar.current
        var ends: [Date] = []
        for log in logs where log.event_type == "sleep" {
            guard let endStr = log.end_time, let end = parseDate(endStr) else { continue }
            if cal.isDate(end, inSameDayAs: day) { ends.append(end) }
        }
        return ends.min()
    }

    private func sectionSleepMinutes(_ section: LogDaySection) -> Int {
        let cal = Calendar.current
        let now = Date()
        let isToday = cal.isDateInToday(section.day)
        var total = 0

        for log in section.items where log.event_type == "sleep" {
            if let dur = log.duration_minutes {
                total += dur
            } else if isToday, log.is_active, let start = parseDate(log.start_time) {
                let dur = Int(now.timeIntervalSince(start) / 60)
                if dur > 0 { total += dur }
            }
        }
        return max(0, total)
    }

    private func sectionSleepHeaderText(_ section: LogDaySection) -> String {
        let total = sectionSleepMinutes(section)
        guard total > 0 else { return "—" }
        return AnalyticsFormatters.sleepDuration(total)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // === ШАПКА С АНАЛИТИКОЙ (без фикс. высоты — нет пустой полосы под кнопкой) ===
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 0) {
                        trackerHeroColumn(
                            title: sleepColumnTitle,
                            systemImage: "moon.fill",
                            value: sleepDurationHero
                        )
                        Rectangle()
                            .fill(FamilyAppStyle.hairline)
                            .frame(width: 1, height: 40)
                        trackerHeroColumn(
                            title: "ЭПИЗОДОВ",
                            systemImage: "repeat",
                            value: episodesHero
                        )
                        Rectangle()
                            .fill(FamilyAppStyle.hairline)
                            .frame(width: 1, height: 40)
                        trackerHeroColumn(
                            title: "ПРОБУЖДЕНИЕ",
                            systemImage: "sun.max.fill",
                            value: firstWakeClockHero
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .pvlPixsoHeroPanel()
                    .padding(.horizontal)
                    
                    Button(action: { navigateToStats = true }) {
                        Text("Аналитика")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FamilyAppStyle.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal)
                    .navigationDestination(isPresented: $navigateToStats) {
                        TrackerAnalyticsHubView()
                    }
                }
                
                // === СПИСОК ===
                Group {
                    if isLoading && logs.isEmpty {
                        ProgressView("Загрузка...")
                    } else if logs.isEmpty {
                        ContentUnavailableView("Нет записей", systemImage: "clock.badge.exclamationmark", description: Text("Нажмите +, чтобы добавить"))
                    } else {
                        List {
                            ForEach(logDaySections) { section in
                                let n = section.items.count
                                Section {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, log in
                                        LogCard(log: log, isLastInGroup: index == n - 1)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                            .listRowSeparator(.hidden, edges: .all)
                                            .listRowBackground(
                                                PVLGroupedRowBackground(
                                                    isFirst: index == 0,
                                                    isLast: index == n - 1,
                                                    isSingle: n == 1
                                                )
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedLog = log
                                                showingAddSheet = true
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) { deleteLog(id: log.id) } label: { Label("Удалить", systemImage: "trash") }
                                                Button { selectedLog = log; showingAddSheet = true } label: { Label("Изменить", systemImage: "pencil") }.tint(FamilyAppStyle.accent)
                                            }
                                    }
                                } header: {
                                    HStack {
                                        Text(section.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(FamilyAppStyle.sectionHeaderForeground)
                                        Spacer()
                                        Text(sectionSleepHeaderText(section))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(FamilyAppStyle.captionMuted)
                                    }
                                    .textCase(nil)
                                }
                            }
                            if hasMoreLogs {
                                Section {
                                    HStack {
                                        Spacer()
                                        if isLoadingMoreLogs {
                                            ProgressView()
                                        } else {
                                            Color.clear
                                                .frame(height: 1)
                                                .onAppear { loadMoreLogsIfNeeded() }
                                        }
                                        Spacer()
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .listRowSpacing(0)
                        .listSectionSpacing(8)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .background(FamilyAppStyle.screenBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
                            .foregroundColor(FamilyAppStyle.accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        selectedLog = nil; preselectedType = nil; showingAddSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(FamilyAppStyle.accent)
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
                        .id(selectedLog?.id ?? -1)
                }
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Ошибка") }
            .onAppear {
                // Не перезагружаем данные при каждом открытии/возврате.
                if !didRunInitialTrackerLoad {
                    didRunInitialTrackerLoad = true
                    loadLogs()
                } else if shouldReloadLogsOnAppear() {
                    loadLogs()
                }
            }
            .refreshable {
                loadLogs()
            }
        }
    }
    
    private static let logsPageLimit = 100
    private static let logsReloadTTL: TimeInterval = 30
    private static let hhmmFormatterRU: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dayTitleFormatterRU: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM"
        return f
    }()
    private static let shortDateFormatterRU: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private func shouldReloadLogsOnAppear() -> Bool {
        guard !isLoading, !isLoadingMoreLogs else { return false }
        guard let last = lastLogsLoadedAt else { return true }
        return Date().timeIntervalSince(last) > Self.logsReloadTTL
    }
    
    private func logsListURL(appendPage: Bool) -> URL? {
        guard var c = URLComponents(string: "\(authManager.baseURL)/tracker/logs") else { return nil }
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(Self.logsPageLimit)")]
        if appendPage, let cur = nextLogsCursor {
            q.append(URLQueryItem(name: "after_start_time", value: cur.startISO))
            q.append(URLQueryItem(name: "after_id", value: "\(cur.id)"))
        }
        c.queryItems = q
        return c.url
    }
    
    func loadLogs(reset: Bool = true) {
        guard let token = authManager.token else {
            errorMessage = "Нет авторизации"; showErrorAlert = true; return
        }
        if reset {
            isLoading = true
            hasMoreLogs = false
            nextLogsCursor = nil
            isLoadingMoreLogs = false
        } else {
            isLoadingMoreLogs = true
        }
        
        let append = !reset
        guard let url = logsListURL(appendPage: append) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if reset {
                    isLoading = false
                } else {
                    isLoadingMoreLogs = false
                }
                if let error = error {
                    errorMessage = error.localizedDescription; showErrorAlert = true; return
                }
                
                guard let data = data else {
                    errorMessage = "Пустой ответ"; showErrorAlert = true; return
                }
                
                do {
                    let page = try JSONDecoder().decode(LogsListPage.self, from: data)
                    if append {
                        self.logs.append(contentsOf: page.items)
                    } else {
                        self.logs = page.items
                    }
                    self.hasMoreLogs = page.has_more
                    if let last = page.items.last {
                        self.nextLogsCursor = (last.start_time, last.id)
                    } else {
                        self.nextLogsCursor = nil
                    }
                    print("✅ Логов на странице: \(page.items.count), has_more: \(page.has_more)")
                    self.loadDailyStats(for: self.selectedDate, from: self.logs)
                    self.refreshLogDaySections(from: self.logs)
                    if reset { self.lastLogsLoadedAt = Date() }
                } catch {
                    errorMessage = "Ошибка данных: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    private func loadMoreLogsIfNeeded() {
        guard hasMoreLogs, !isLoadingMoreLogs, !isLoading else { return }
        loadLogs(reset: false)
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
    
    func formatDateShort(_ date: Date) -> String {
        Self.shortDateFormatterRU.string(from: date)
    }
    
    func parseDate(_ string: String) -> Date? {
        PVLDateParsing.parse(string)
    }
}

struct LogCard: View {
    let log: TrackerView.BabyLog
    /// Склейка строк в одном дне: линия между «подкарточками».
    var isLastInGroup: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconBackground)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(typeTint)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(typeTitle)
                        .font(.system(size: 15, weight: .semibold))
                    if log.is_active {
                        Text("активно")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(FamilyAppStyle.incomeGreen)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(FamilyAppStyle.incomeSoftBadgeBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                Text(timeRangeText)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(FamilyAppStyle.captionMuted)
                    .lineLimit(2)
            }

            Spacer()

            if let durationText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(durationText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(durationTint)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLastInGroup {
                Rectangle()
                    .fill(FamilyAppStyle.hairline)
                    .frame(height: 1)
            }
        }
    }

    private var typeTint: Color {
        log.event_type == "sleep" ? FamilyAppStyle.accent : .orange
    }

    private var typeIcon: String {
        log.event_type == "sleep" ? "moon.fill" : "drop.fill"
    }

    private var typeTitle: String {
        log.event_type == "sleep" ? "Сон" : "Кормление"
    }

    private var iconBackground: Color {
        log.event_type == "sleep"
            ? FamilyAppStyle.softIconPurple
            : FamilyAppStyle.softIconOrange
    }

    private var timeRangeText: String {
        let start = PVLDateParsing.timeHHmm(from: log.start_time)
        let end: String
        if let endS = log.end_time {
            end = PVLDateParsing.timeHHmm(from: endS)
        } else {
            end = log.is_active ? "сейчас" : "—"
        }
        return "\(start) — \(end)"
    }

    private var durationText: String? {
        guard log.event_type == "sleep" else { return nil }
        guard let dur = log.duration_minutes, dur > 0 else { return nil }
        return AnalyticsFormatters.sleepDuration(dur)
    }

    private var durationTint: Color {
        FamilyAppStyle.accent
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
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
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
