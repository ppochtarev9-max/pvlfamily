import SwiftUI

/// Единая палитра экранов (дашборд, вкладки) — iOS 26, Liquid Glass + светлые карточки.
enum FamilyAppStyle {
    static let screenBackground = Color(.systemGray6)
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    /// Верхние «геро»-карточки (баланс, суточная статистика)
    static let heroCardFill = Color(red: 0.94, green: 0.97, blue: 1.0)
    static let cardStroke = Color(red: 0.75, green: 0.86, blue: 0.98)
    /// Рядки списка / карточки операций
    static let listCardFill = Color(.systemBackground)
}

extension View {
    /// Единый фон для `List` / `Form`, как на вкладках.
    func pvlFormScreenStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(FamilyAppStyle.screenBackground)
    }
}
