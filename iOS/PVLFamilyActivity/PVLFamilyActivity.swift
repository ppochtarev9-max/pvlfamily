import WidgetKit
import SwiftUI
import ActivityKit

// 1. Используем обычный TimelineProvider
struct SleepActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 3600, statusText: "Спит")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 3600, statusText: "Спит")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        // В реальном приложении здесь нужно брать данные из контейнера App Group
        let entry = SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 0, statusText: "Загрузка...")
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let isSleeping: Bool
    let startTime: Date
    let elapsedSeconds: Int
    let statusText: String
}

// 2. Конфигурация виджета
struct PVLFamilyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // ... Ваш код интерфейса (Lock Screen) ...
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                        .font(.title2).foregroundColor(context.state.isSleeping ? .purple : .orange)
                    Text(context.state.statusText).font(.headline).bold()
                    Spacer()
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(.title2, design: .rounded)).monospacedDigit().foregroundColor(.secondary)
                }
                if context.state.isSleeping {
                    Text("Начало: \(formatDate(context.state.startTime))").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            // ... Ваш код Dynamic Island ...
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.statusText).font(.headline)
                        Text(formatTime(context.state.elapsedSeconds)).font(.title3).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                        .font(.title2).foregroundColor(context.state.isSleeping ? .purple : .orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Откройте приложение").font(.caption).foregroundColor(.gray)
                }
            } compactLeading: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds)).font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
            }
            .widgetURL(URL(string: "pvlfamily://open_tracker"))
        }
    }
}

// Хелперы
func formatTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
func formatDate(_ date: Date) -> String {
    let f = DateFormatter(); f.timeStyle = .short; f.locale = Locale(identifier: "ru_RU")
    return f.string(from: date)
}
