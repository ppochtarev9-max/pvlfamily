import WidgetKit
import AppIntents

// --- ИНТЕНТ: ЗАВЕРШИТЬ СОН ---
struct FinishSleepIntent: AppIntent {
    static var title: LocalizedStringResource { "Завершить сон" }
    
    func perform() async throws -> some IntentResult {
        // В виджете мы не можем напрямую менять UI или делать сетевые запросы надежно.
        // Лучшая стратегия: открыть приложение на экране трекера, где сработает логика.
        // Но для мгновенного отклика можно попробовать отправить уведомление или использовать SharedDefaults.
        
        // Пока просто откроем приложение (это стандартное поведение для кнопок в Live Activity без сложной настройки)
        // Если нужно реальное действие без открытия - требуется сложная настройка App Group и Background Tasks.
        
        return .result()
    }
}

// --- ИНТЕНТ: НАЧАТЬ СОН ---
struct StartSleepIntent: AppIntent {
    static var title: LocalizedStringResource { "Начать сон" }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
