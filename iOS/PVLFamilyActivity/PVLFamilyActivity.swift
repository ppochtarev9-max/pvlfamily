import WidgetKit
import SwiftUI
import ActivityKit
import OSLog // Для логов внутри виджета

// Создаем логгер для отладки виджета
let widgetLogger = OSLog(subsystem: "com.pvlfamily.PVLFamily", category: "LiveActivityWidget")

// 1. ПРОВАЙДЕР ДАННЫХ
struct SleepActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        os_log("🟢 [Widget] Placeholder generated", log: widgetLogger, type: .info)
        return SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 3600, statusText: "Спит")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        os_log("🟡 [Widget] Snapshot requested", log: widgetLogger, type: .info)
        let entry = SimpleEntry(date: Date(), isSleeping: true, startTime: Date(), elapsedSeconds: 3600, statusText: "Спит")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        os_log("🔵 [Widget] Timeline requested", log: widgetLogger, type: .info)
        // В реальном приложении данные берутся из контекста activity, а не генерируются заново
        // Здесь мы просто передаем текущее состояние, которое придет от системы
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

// 2. КОНФИГУРАЦИЯ ВИДЖЕТА
struct PVLFamilyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // Логирование получения контекста (Lock Screen)
            // Примечание: os_log здесь может работать нестабильно в зависимости от версии iOS,
            // но попытка записать лог допустима.
            
            // ЭКРАН БЛОКИРОВКИ
            VStack(spacing: 12) {
                HStack {
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
                        .foregroundColor(.secondary)
                }

                if context.state.isSleeping {
                    Text("Начало: \(formatDate(context.state.startTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Бодрствует")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            // DYNAMIC ISLAND
            DynamicIsland {
                // Расширенный вид
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.statusText).font(.headline)
                        Text(formatTime(context.state.elapsedSeconds))
                            .font(.title3)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                        .font(.title2)
                        .foregroundColor(context.state.isSleeping ? .purple : .orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Нажмите, чтобы открыть приложение")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } compactLeading: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isSleeping ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(context.state.isSleeping ? .purple : .orange)
            }
            .widgetURL(URL(string: "pvlfamily://open_tracker"))
            // onAppear внутри DynamicIsland недоступен в старых версиях SDK или требует специфики.
            // Убрали его, чтобы избежать ошибки компиляции.
        }
    }
}

// Хелперы
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

// Preview
#if DEBUG
struct PVLFamilyLiveActivity_Previews: PreviewProvider {
    static var attributes: SleepActivityAttributes {
        SleepActivityAttributes(childName: "Малыш")
    }

    static var contentState: SleepActivityAttributes.ContentState {
        SleepActivityAttributes.ContentState(
            isSleeping: true,
            startTime: Date(),
            elapsedSeconds: 125,
            statusText: "Ребенок спит"
        )
    }

    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
    }
}
#endif
