import SwiftUI
import UserNotifications

@main
struct PVLFamilyApp: App {
    @StateObject var authManager = AuthManager()
    @StateObject var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(notificationManager)
                .onAppear {
                    // Запрос прав при старте приложения
                    notificationManager.requestPermission()
                    
                    // Настройка делегата для обработки действий с уведомлениями (опционально)
                    UNUserNotificationCenter.current().delegate = UserNotificationCenterDelegate.shared
                }
        }
    }
}

// Делегат для обработки нажатий на уведомления (если нужно будет действие по клику)
class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationCenterDelegate()
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Показывать уведомление даже если приложение открыто
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Обработка нажатия на уведомление
        completionHandler()
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isLoggedIn {
                MainTabView() // Убедись, что этот вид существует
            } else {
                LoginView() // Убедись, что этот вид существует
            }
        }
    }
}
