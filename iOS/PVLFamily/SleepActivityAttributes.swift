import ActivityKit
import Foundation

public struct SleepActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isSleeping: Bool
        public var startTime: Date
        public var elapsedSeconds: Int
        public var statusText: String
        
        // Кодирование даты для ActivityKit
        private enum CodingKeys: String, CodingKey {
            case isSleeping, startTime, elapsedSeconds, statusText
        }
    }

    public var childName: String
}
