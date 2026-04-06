import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "chart.pie.fill")
                    Text("Главная")
                }

            BudgetView()
                .tabItem {
                    Image(systemName: "dollarsign.circle.fill")
                    Text("Бюджет")
                }

            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Календарь")
                }
            
            // --- НОВАЯ ВКЛАДКА: ТРЕКЕР ---
            TrackerView()
                .tabItem {
                    Image(systemName: "heart.fill") // Заменили baby.carriage на heart
                    Text("Трекер")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Профиль")
                }
        }
    }
}
