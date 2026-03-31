import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            BudgetView()
                .tabItem { Label("Бюджет", systemImage: "dollarsign.circle.fill") }
            CalendarView()
                .tabItem { Label("Календарь", systemImage: "calendar") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.circle") }
        }
    }
}
