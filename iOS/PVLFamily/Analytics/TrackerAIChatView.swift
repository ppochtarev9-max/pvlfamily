import SwiftUI

/// Чат с ИИ по трекеру (пока использует client-built safe_payload из /tracker/stats).
struct TrackerAIChatView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var errorText: String?
    @State private var messages: [ChatMessage] = []

    // Контекст для LLM (подтягиваем 60 дней, как и в хабе).
    @State private var longStats: TrackerStats?
    @State private var todayStats: TrackerStats?

    var body: some View {
        VStack(spacing: 0) {
            chatBody
            Divider().opacity(0.4)
            composer
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("ИИ по трекеру")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if messages.isEmpty {
                messages = [.assistant("Задай вопрос про сон за последние недели: тренд, сравнение, выбросы, рекомендации.")]
            }
            if longStats == nil || todayStats == nil {
                loadContext()
            }
        }
    }

    private var chatBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if let err = errorText {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) {
                            inputText = chip
                            send(question: chip)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Напиши вопрос…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isSending)

                Button {
                    send(question: inputText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(FamilyAppStyle.screenBackground)
    }

    private var chips: [String] {
        [
            "Почему последние 2 недели сон хуже/лучше, чем предыдущие?",
            "В какие дни недели сон обычно лучше?",
            "Есть ли выбросы по короткому сну и как часто они случаются?",
            "Какие 3 рекомендации можно попробовать на этой неделе?"
        ]
    }

    private func loadContext() {
        authManager.getTrackerStats(days: 1) { r in
            DispatchQueue.main.async { if case .success(let s) = r { todayStats = s } }
        }
        authManager.getTrackerStats(days: 60) { r in
            DispatchQueue.main.async { if case .success(let s) = r { longStats = s } }
        }
    }

    private func send(question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if isSending { return }
        isSending = true
        errorText = nil

        messages.append(.user(q))
        inputText = ""

        guard let today = todayStats, let longWindow = longStats else {
            isSending = false
            errorText = "Контекст ещё загружается… попробуй через секунду."
            return
        }

        let monthSlice = thisMonthSlice(from: longWindow)
        let series = buildTrackerSeries(from: longWindow.daily_breakdown)
        let breakdowns = buildTrackerBreakdowns(from: longWindow.daily_breakdown)
        let comparisons = buildTrackerComparisons(from: longWindow.daily_breakdown)

        let payload = InsightPayload(
            report_type: "tracker",
            period: "recent_window",
            metrics: [
                "sleep_today_minutes": Double(today.total_sleep_minutes),
                "sessions_today": Double(today.total_sessions),
                "sleep_month_minutes": Double(monthSlice?.minutes ?? 0),
                "days_with_data_month": Double(monthSlice?.days ?? 0)
            ],
            trend_flags: [
                (monthSlice?.minutes ?? 0) > 0 ? "month_has_data" : "month_no_data",
                today.total_sleep_minutes > 0 ? "day_has_sleep" : "day_no_sleep"
            ],
            anomalies: trackerAnomalies(from: longWindow.daily_breakdown),
            series: series.isEmpty ? nil : series,
            breakdowns: breakdowns.isEmpty ? nil : breakdowns,
            comparisons: comparisons.isEmpty ? nil : comparisons,
            notes: "safe_payload_only"
        )

        authManager.getInsight(
            kind: "tracker",
            payload: payload,
            provider: nil,
            question: q,
            anchorMonth: nil,
            windowMonths: nil,
            userId: nil
        ) { result in
            DispatchQueue.main.async {
                isSending = false
                switch result {
                case .success(let r):
                    messages.append(.assistant(renderResponse(r)))
                case .failure(let e):
                    errorText = e.localizedDescription
                    messages.append(.assistant("Не получилось получить ответ. Попробуй ещё раз."))
                }
            }
        }
    }

    private func renderResponse(_ r: InsightResponse) -> String {
        var parts: [String] = []
        if !r.summary_today.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(r.summary_today.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !r.summary_month.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(r.summary_month.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !r.bullets.isEmpty {
            parts.append(r.bullets.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !r.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Источник: \(r.provider)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func thisMonthSlice(from stats: TrackerStats) -> (minutes: Int, days: Int, sessions: Int)? {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        var min = 0, days = 0, ses = 0
        for d in stats.daily_breakdown {
            let parts = d.date.split(separator: "-")
            guard parts.count == 3,
                  let yy = Int(parts[0]), let mm = Int(parts[1]) else { continue }
            if yy == y && mm == m {
                min += d.sleep_minutes
                ses += d.sessions_count
                if d.sleep_minutes > 0 { days += 1 }
            }
        }
        return (min, days, ses)
    }

    private func buildTrackerSeries(from days: [DailyStat]) -> [InsightSeries] {
        let ordered = days.sorted { $0.date < $1.date }
        let withData = ordered.filter { $0.sleep_minutes > 0 }
        if withData.isEmpty { return [] }
        let last = Array(withData.suffix(30))
        let points = last.map { InsightPoint(t: $0.date, v: Double($0.sleep_minutes)) }
        return [InsightSeries(name: "Сон по дням (мин)", points: points, unit: "minutes")]
    }

    private func buildTrackerComparisons(from days: [DailyStat]) -> [InsightComparison] {
        let ordered = days.sorted { $0.date < $1.date }.filter { $0.sleep_minutes > 0 }
        guard ordered.count >= 14 else { return [] }
        let last14 = Array(ordered.suffix(14))
        let prev7 = Array(last14.prefix(7))
        let cur7 = Array(last14.suffix(7))
        let prevSum = Double(prev7.map(\.sleep_minutes).reduce(0, +))
        let curSum = Double(cur7.map(\.sleep_minutes).reduce(0, +))
        let delta = curSum - prevSum
        let deltaPct = prevSum > 0 ? (delta / prevSum) * 100 : nil
        return [
            InsightComparison(
                name: "Сон: 7 дней vs предыдущие 7",
                a_label: "последние 7",
                a_value: curSum,
                b_label: "предыдущие 7",
                b_value: prevSum,
                delta: delta,
                delta_pct: deltaPct,
                unit: "minutes"
            )
        ]
    }

    private func buildTrackerBreakdowns(from days: [DailyStat]) -> [InsightBreakdown] {
        let vals = days.map(\.sleep_minutes).filter { $0 > 0 }
        guard vals.count >= 5 else { return [] }

        func bucket(_ minutes: Int) -> String {
            if minutes < 300 { return "<5ч" }
            if minutes < 390 { return "5–6.5ч" }
            if minutes < 480 { return "6.5–8ч" }
            if minutes < 600 { return "8–10ч" }
            return "10ч+"
        }

        var counts: [String: Int] = [:]
        for v in vals { counts[bucket(v), default: 0] += 1 }
        let total = Double(vals.count)

        let order = ["<5ч", "5–6.5ч", "6.5–8ч", "8–10ч", "10ч+"]
        let items: [InsightBreakdownItem] = order.compactMap { name in
            guard let c = counts[name], c > 0 else { return nil }
            return InsightBreakdownItem(name: name, value: Double(c), share: Double(c) / total)
        }
        if items.isEmpty { return [] }
        return [InsightBreakdown(name: "Распределение сна по длительности (дни)", items: items, unit: "days")]
    }

    private func trackerAnomalies(from days: [DailyStat]) -> [[String: Double]] {
        let vals = days.filter { $0.sleep_minutes > 0 }.map { Double($0.sleep_minutes) }
        guard vals.count > 2 else { return [] }
        let mean = vals.reduce(0, +) / Double(vals.count)
        let variance = vals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(vals.count)
        let sd = sqrt(variance)
        guard sd > 1 else { return [] }
        let highCount = days.filter { Double($0.sleep_minutes) > mean + 1.2 * sd }.count
        let lowCount = days.filter { $0.sleep_minutes > 0 && Double($0.sleep_minutes) < mean - 1.2 * sd }.count
        return [["high_outliers": Double(highCount), "low_outliers": Double(lowCount)]]
    }
}

