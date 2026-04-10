import WidgetKit
import SwiftUI
import ActivityKit
import OSLog

let widgetLogger = OSLog(subsystem: "com.pvlfamily.PVLFamily", category: "LiveActivityWidget")

// --- МОДЕЛИ ДАННЫХ ---
struct SimpleEntry: TimelineEntry {
    let date: Date
    let isSleeping: Bool
    let startTime: Date // Время начала текущего состояния (сна или бодрствования)
    let elapsedSeconds: Int
    let statusText: String
}

// --- ПРОВАЙДЕР ---
struct SleepActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 3600, statusText: "Спит")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), isSleeping: false, startTime: Date(), elapsedSeconds: 120, statusText: "Бодрствует")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        // В реальном приложении данные придут из контента активности
        let entry = SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 0, statusText: "Загрузка...")
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

// --- КОНФИГУРАЦИЯ ВИДЖЕТА ---
struct PVLFamilyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // --- ЭКРАН БЛОКИРОВКИ ---
            VStack(spacing: 12) {
                HStack {
                    // Иконка меняется в зависимости от состояния
                    Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                        .font(.title2)
                        .foregroundColor(context.state.isSleeping ? .purple : .orange)

                    Text(context.state.statusText)
                        .font(.headline)
                        .bold()

                    Spacer()

                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(.title2, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(context.state.isSleeping ? .purple : .orange)
                }

                if context.state.isSleeping {
                    Text("Спит с \(formatDate(context.state.startTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Бодрствует с \(formatDate(context.state.startTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
            .activitySystemActionForegroundColor(.primary)
            .containerBackground(.fill.tertiary, for: .widget)

        } dynamicIsland: { context in
            DynamicIsland {
                // --- DYNAMIC ISLAND EXPANDED ---
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.statusText)
                            .font(.headline)
                        Text(formatTime(context.state.elapsedSeconds))
                            .font(.title3)
                            .monospacedDigit()
                            .foregroundColor(context.state.isSleeping ? .purple : .orange)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                        .font(.title2)
                        .foregroundColor(context.state.isSleeping ? .purple : .orange)
                }
                
                // --- КНОПКИ ВНИЗУ ---
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 20) {
                        if context.state.isSleeping {
                            // Кнопка: Завершить сон (начать бодрствование)
                            Button(action: {}) {
                                Label("Завершить", systemImage: "checkmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.purple.opacity(0.2)))
                                    .foregroundColor(.purple)
                            }
                            .widgetURL(URL(string: "pvlfamily://finish_sleep"))
                        } else {
                            // Кнопка: Начать сон
                            Button(action: {}) {
                                Label("Уложить", systemImage: "moon.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.orange.opacity(0.2)))
                                    .foregroundColor(.orange)
                            }
                            .widgetURL(URL(string: "pvlfamily://start_sleep"))
                        }
                        
                        // Кнопка: Кормление (всегда доступна)
                        Button(action: {}) {
                            Label("Кормление", systemImage: "drop.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.blue.opacity(0.2)))
                                .foregroundColor(.blue)
                        }
                        .widgetURL(URL(string: "pvlfamily://quick_feed"))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
                    .widgetURL(URL(string: "pvlfamily://open_tracker"))
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.caption2)
                    .monospacedDigit()
                    .widgetURL(URL(string: "pvlfamily://open_tracker"))
            } minimal: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
            }
        }
    }
}

// --- ХЕЛПЕРЫ ---
func formatTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}

func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.locale = Locale(identifier: "ru_RU")
    return f.string(from: date)
}

#if DEBUG
struct PVLFamilyLiveActivity_Previews: PreviewProvider {
    static var attributes: SleepActivityAttributes {
        SleepActivityAttributes(childName: "Малыш")
    }

    static var contentStateSleep: SleepActivityAttributes.ContentState {
        SleepActivityAttributes.ContentState(
            isSleeping: true,
            startTime: Date().addingTimeInterval(-3600),
            elapsedSeconds: 3600,
            statusText: "Спит"
        )
    }
    
    static var contentStateAwake: SleepActivityAttributes.ContentState {
        SleepActivityAttributes.ContentState(
            isSleeping: false,
            startTime: Date().addingTimeInterval(-125),
            elapsedSeconds: 125,
            statusText: "Бодрствует"
        )
    }

    static var previews: some View {
        attributes
            .previewContext(contentStateSleep, viewKind: .dynamicIsland(.expanded))
        attributes
            .previewContext(contentStateAwake, viewKind: .dynamicIsland(.expanded))
    }
}
#endif
