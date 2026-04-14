import SwiftUI
import UserNotifications

@main
struct PVLFamilyApp: App {
    @StateObject var authManager = AuthManager()
    @StateObject var notificationManager = NotificationManager.shared
    
    init() {
         // ПРОВЕРКА НА ЗАПУСК ИЗ-ПОД ТЕСТОВ
         if ProcessInfo.processInfo.arguments.contains("--reset-app-state") {
             UserDefaults.standard.removeObject(forKey: "userToken")
             UserDefaults.standard.removeObject(forKey: "userName")
             UserDefaults.standard.removeObject(forKey: "userId")
             UserDefaults.standard.removeObject(forKey: "savedServerMode")
             print("🧪 Тестовый режим: состояние сброшено")
         }
        
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // Очищаем UserDefaults (здесь хранится токен и настройки)
            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
                UserDefaults.standard.synchronize()
            }
            print("🧹 [UITEST] Данные сброшены для чистого запуска.")
        }
  
     }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(notificationManager)
                .onAppear {
                    notificationManager.requestPermission()
                    UNUserNotificationCenter.current().delegate = UserNotificationCenterDelegate.shared
                }
                // ДОБАВЛЕНО: Обработка глубоких ссылок из виджета
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    // Функция обработки ссылок
    func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        
        // Отправляем уведомление внутрь приложения, чтобы DashboardView мог отреагировать
        // Так как у нас нет прямого доступа к состоянию DashboardView отсюда
        NotificationCenter.default.post(name: NSNotification.Name("WidgetActionTriggered"), object: host)
        
        print("🔗 Deep Link received: \(host)")
    }
}

// ... остальной код (Delegate, ContentView) без изменений ...
class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationCenterDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    var body: some View {
        Group {
            if authManager.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}
