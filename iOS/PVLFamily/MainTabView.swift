import SwiftUI

/// Корневой `TabView`: iOS 26 — системный таббар с Liquid Glass (стандартные `Tab` + `sidebarAdaptable`).
/// Не кастомный `ZStack`: состояние вкладок хранит сам `TabView`.

private enum MainTab: String, Hashable, CaseIterable, Sendable {
    case home, budget, diary, tracker, profile

    /// Подписи в интерфейсе (не all-caps — так лучше с системной типографикой iOS 26).
    var title: String {
        switch self {
        case .home: "Главная"
        case .budget: "Бюджет"
        case .diary: "Дневник"
        case .tracker: "Трекер"
        case .profile: "Профиль"
        }
    }

    /// Набор иконок «посвежее» (SF Symbols), в таббаре хорошо читается с `symbolRenderingMode`.
    var systemImage: String {
        switch self {
        case .home: "house.lodge.fill"
        case .budget: "wallet.bifold.fill"
        case .diary: "book.pages.fill"
        case .tracker: "figure.and.child.holdinghands"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct MainTabView: View {
    @State private var selected: MainTab = .home

    var body: some View {
        TabView(selection: $selected) {
            Tab(MainTab.home.title, systemImage: MainTab.home.systemImage, value: MainTab.home) {
                DashboardView()
            }
            Tab(MainTab.budget.title, systemImage: MainTab.budget.systemImage, value: MainTab.budget) {
                BudgetView()
            }
            Tab(MainTab.diary.title, systemImage: MainTab.diary.systemImage, value: MainTab.diary) {
                CalendarView()
            }
            Tab(MainTab.tracker.title, systemImage: MainTab.tracker.systemImage, value: MainTab.tracker) {
                TrackerView()
            }
            Tab(MainTab.profile.title, systemImage: MainTab.profile.systemImage, value: MainTab.profile) {
                ProfileView()
            }
        }
        .tint(FamilyAppStyle.accent)
        .tabViewStyle(.sidebarAdaptable)
        // Таббар «отъезжает» при прокрутке вниз, как в приложениях Apple на iOS 26.
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
        .environmentObject(NotificationManager.shared)
}
