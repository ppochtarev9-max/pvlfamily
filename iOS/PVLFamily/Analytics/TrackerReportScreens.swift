import SwiftUI
import Foundation

// MARK: - Сравнение двух последних недель

struct TrackerCompareWeeksReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats { weeksContent(s) }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Неделя к неделе")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func weeksContent(_ s: TrackerStats) -> some View {
        let parts = twoWeeksSplit(s.daily_breakdown)
        let diff = parts.1 - parts.0
        reportScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Сравнение: предыдущие 7 дней vs последние 7 дней (по дате).")
                    .font(.subheadline)
                    .foregroundStyle(FamilyAppStyle.captionMuted)
                HStack(alignment: .top) {
                    weekColumn(title: "Раньше (ранние 7 в окне 14д)", minutes: parts.0, days: 7)
                    weekColumn(title: "Позже (последние 7)", minutes: parts.1, days: 7)
                }
                Text(diff >= 0 ? "Во второй неделе суммарно на \(AnalyticsFormatters.sleepDuration(abs(diff))) дольше." : "Во второй неделе суммарно на \(AnalyticsFormatters.sleepDuration(abs(diff))) меньше.")
                    .font(.footnote)
                    .foregroundStyle(FamilyAppStyle.captionMuted)
            }
        }
    }

    private func twoWeeksSplit(_ days: [DailyStat]) -> (Int, Int) {
        let sorted = days.sorted { $0.date < $1.date }
        let first7 = Array(sorted.prefix(7))
        let last7 = Array(sorted.suffix(min(7, sorted.count)))
        return (
            first7.map(\.sleep_minutes).reduce(0, +),
            last7.map(\.sleep_minutes).reduce(0, +)
        )
    }

    private func weekColumn(title: String, minutes: Int, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(AnalyticsFormatters.sleepDuration(minutes))
                .font(.title2.weight(.bold))
            Text("Σ минут / ~7 дн.")
                .font(.caption2)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 14) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: - Средние (7 / 30 дней)

struct TrackerAveragesReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var s7: TrackerStats?
    @State private var s30: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let a = s7, a.total_sessions > 0 {
                            row("7 дней", avg: a.total_sleep_minutes / a.total_sessions, perDay: a.total_sleep_minutes / 7)
                        }
                        if let b = s30, b.total_sessions > 0 {
                            row("30 дней", avg: b.total_sleep_minutes / b.total_sessions, perDay: b.total_sleep_minutes / 30)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Средние за период")
        .onAppear(perform: load)
    }

    private func row(_ title: String, avg: Int, perDay: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("Средний эпизод: \(AnalyticsFormatters.sleepDuration(avg))")
            Text("Средне за сутки (Σ/дни): \(AnalyticsFormatters.sleepDuration(perDay))")
                .font(.footnote)
                .foregroundStyle(FamilyAppStyle.captionMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() {
        isLoading = true
        let g = DispatchGroup()
        g.enter()
        authManager.getTrackerStats(days: 7) { r in defer { g.leave() }; if case .success(let s) = r { s7 = s } }
        g.enter()
        authManager.getTrackerStats(days: 30) { r in defer { g.leave() }; if case .success(let s) = r { s30 = s } }
        g.notify(queue: .main) {
            isLoading = false
        }
    }
}

// MARK: - Выбросы (дни с аномальным сном)

struct TrackerOutlierDaysReportView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var stats: TrackerStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if let error { ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else if let s = stats {
                let out = Self.outliers(from: s.daily_breakdown)
                List {
                    Section("Сильно выше нормы") {
                        if out.high.isEmpty { Text("—").foregroundStyle(.secondary) }
                        ForEach(out.high, id: \.date) { d in
                            HStack {
                                Text(formatDay(d.date))
                                Spacer()
                                Text(AnalyticsFormatters.sleepDuration(d.sleep_minutes))
                            }
                        }
                    }
                    Section("Сильно ниже нормы") {
                        if out.low.isEmpty { Text("—").foregroundStyle(.secondary) }
                        ForEach(out.low, id: \.date) { d in
                            HStack {
                                Text(formatDay(d.date))
                                Spacer()
                                Text(AnalyticsFormatters.sleepDuration(d.sleep_minutes))
                            }
                        }
                    }
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Дни-выбросы")
        .onAppear(perform: load)
    }

    private static func outliers(from days: [DailyStat]) -> (high: [DailyStat], low: [DailyStat]) {
        let vals = days.filter { $0.sleep_minutes > 0 }.map { $0.sleep_minutes }
        guard vals.count > 2 else { return ([], []) }
        let mean = Double(vals.reduce(0, +)) / Double(vals.count)
        let varc = vals.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(vals.count)
        let sd = sqrt(varc)
        guard sd > 1 else { return ([], []) }
        let hi = days.filter { Double($0.sleep_minutes) > mean + 1.2 * sd }
        let lo = days.filter { $0.sleep_minutes > 0 && Double($0.sleep_minutes) < mean - 1.2 * sd }
        return (hi, lo)
    }

    private func formatDay(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter()
        o.dateFormat = "dd.MM"
        o.locale = Locale(identifier: "ru_RU")
        return o.string(from: d)
    }

    private func load() {
        isLoading = true
        authManager.getTrackerStats(days: 60) { r in
            isLoading = false
            switch r {
            case .success(let s): stats = s
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}
