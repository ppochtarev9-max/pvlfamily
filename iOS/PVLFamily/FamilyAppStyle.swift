import SwiftUI

/// Единая палитра экранов (дашборд, вкладки) — iOS 26, Liquid Glass + светлые карточки.
enum FamilyAppStyle {
    static let screenBackground = Color(.systemGray6)
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    /// Верхние «геро»-карточки (баланс, суточная статистика)
    static let heroCardFill = Color(red: 0.94, green: 0.97, blue: 1.0)
    static let cardStroke = Color(red: 0.75, green: 0.86, blue: 0.98)
    /// Как в Pixso: белая панель + тень (Frame3183/3332)
    static let heroCardSurface = Color(.systemBackground)
    static let pixsoInk = Color(red: 26 / 255, green: 25 / 255, blue: 24 / 255)
    static let captionMuted = Color(red: 156 / 255, green: 155 / 255, blue: 153 / 255)
    static let incomeGreen = Color(red: 61 / 255, green: 138 / 255, blue: 90 / 255)
    static let expenseCoral = Color(red: 208 / 255, green: 128 / 255, blue: 104 / 255)
    static let hairline = Color(red: 229 / 255, green: 228 / 255, blue: 225 / 255)
    /// Рядки списка / карточки операций
    static let listCardFill = Color(.systemBackground)
}

extension View {
    /// Единый фон для `List` / `Form`, как на вкладках.
    func pvlFormScreenStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(FamilyAppStyle.screenBackground)
    }

    /// Верхняя аналитика: как в `design-pixso-3` (белая карта, 16pt radius, мягкая тень).
    func pvlPixsoHeroPanel() -> some View {
        background(FamilyAppStyle.heroCardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: FamilyAppStyle.pixsoInk.opacity(0.08), radius: 12, x: 0, y: 2)
    }
}

/// Склейка строк «один день — один белый блок» (см. design-pixso-3).
struct PVLGroupedRowBackground: View {
    var isFirst: Bool
    var isLast: Bool
    var isSingle: Bool

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? 14 : 0,
            bottomLeadingRadius: isLast ? 14 : 0,
            bottomTrailingRadius: isLast ? 14 : 0,
            topTrailingRadius: isFirst ? 14 : 0,
            style: .continuous
        )
        .fill(FamilyAppStyle.listCardFill)
        .shadow(
            color: Color.black.opacity(isSingle ? 0.06 : 0),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}
