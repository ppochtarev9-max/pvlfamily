import Foundation
import UserNotifications
import Combine // <-- ВАЖНО: Без этого не работает ObservableObject

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized: Bool = false
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = (settings.authorizationStatus == .authorized)
            }
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    print("✅ Разрешение на уведомления получено")
                } else if let error = error {
                    print("❌ Ошибка: \(error.localizedDescription)")
                } else {
                    print("⚠️ Пользователь отклонил запрос")
                }
            }
        }
    }
    
    func scheduleSleepReminder(startedAt: Date, hours: Double = 8.0) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "💤 Малыш спит"
        content.body = "Прошло уже \(Int(hours)) часов. Не забудьте завершить сон, когда проснется."
        content.sound = .default
        content.categoryIdentifier = "SLEEP_TRACKER"
        
        // Уведомление через N часов после начала сна
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: hours * 3600, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "sleep_reminder_\(startedAt.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Ошибка планирования уведомления: \(error.localizedDescription)")
            } else {
                print("🔔 Уведомление запланировано")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
