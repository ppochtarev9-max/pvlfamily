import ActivityKit
import Foundation

public struct SleepActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isSleeping: Bool
        public var startTime: Date
        public var statusText: String
        public var lastUpdated: Date // Новое поле
        
        // Кодирование даты для ActivityKit
        private enum CodingKeys: String, CodingKey {
            case isSleeping, startTime, statusText, lastUpdated // <--- ДОБАВИТЬ СЮДА
        }
    }

    public var childName: String
}
