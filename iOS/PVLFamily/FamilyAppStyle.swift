import SwiftUI
import UIKit

/// Единая палитра экранов (дашборд, вкладки) — iOS 26, Liquid Glass; токены адаптируются к светлой/тёмной схеме.
enum FamilyAppStyle {
    static let screenBackground = Color(
        UIColor { tc in
            tc.userInterfaceStyle == .dark ? .systemGroupedBackground : .systemGray6
        }
    )

    static let accent = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark {
                return UIColor(red: 100 / 255, green: 165 / 255, blue: 1, alpha: 1)
            }
            return UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        }
    )

    /// Верхние «геро»-карточки (баланс, суточная статистика, трекер)
    static let heroCardFill = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .secondarySystemGroupedBackground }
            return UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
        }
    )

    /// Рамка полей и карточек. В Dark альфа выше, иначе граница «пропадает» вместе с заливкой.
    static let cardStroke = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return UIColor.label.withAlphaComponent(0.42) }
            return UIColor(red: 0.75, green: 0.86, blue: 0.98, alpha: 1)
        }
    )

    /// Поверхности «карточек» в панелях: в Dark не `systemBackground` — сливается с фоном списка.
    static let heroCardSurface = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .secondarySystemGroupedBackground }
            return .systemBackground
        }
    )

    /// Заголовок текста/иконок (раньше фиксированный тёмно-серый)
    static let pixsoInk = Color(UIColor.label)

    static let captionMuted = Color(UIColor.secondaryLabel)

    static let incomeGreen = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark {
                return UIColor(red: 0.42, green: 0.78, blue: 0.58, alpha: 1)
            }
            return UIColor(red: 61 / 255, green: 138 / 255, blue: 90 / 255, alpha: 1)
        }
    )

    static let expenseCoral = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark {
                return UIColor(red: 1, green: 0.55, blue: 0.45, alpha: 1)
            }
            return UIColor(red: 208 / 255, green: 128 / 255, blue: 104 / 255, alpha: 1)
        }
    )

    /// Между строк в группе: в Dark чуть заметнее, чем `separator` на `systemBackground`.
    static let hairline = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return UIColor.label.withAlphaComponent(0.3) }
            return .separator
        }
    )

    /// Рядки списка / плашки: в Dark как у сгруппированной `UITableView` — уровень выше `systemGroupedBackground`.
    static let listCardFill = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .secondarySystemGroupedBackground }
            return .systemBackground
        }
    )

    /// Заголовки секций в списках (день, группа)
    static let sectionHeaderForeground = Color(UIColor.tertiaryLabel)

    /// Обводка крупных карточек (сетка действий и т.п.)
    static let cardChromeBorder = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return UIColor.label.withAlphaComponent(0.4) }
            return UIColor(red: 0.89, green: 0.89, blue: 0.91, alpha: 1)
        }
    )

    /// Мягкие фоны под иконками в списках
    static let softIconGreen = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .systemGreen.withAlphaComponent(0.22) }
            return UIColor(red: 0.94, green: 0.99, blue: 0.96, alpha: 1)
        }
    )
    static let softIconOrange = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .systemOrange.withAlphaComponent(0.22) }
            return UIColor(red: 1, green: 0.97, blue: 0.93, alpha: 1)
        }
    )
    static let softIconPurple = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .systemIndigo.withAlphaComponent(0.24) }
            return UIColor(red: 237 / 255, green: 233 / 255, blue: 254 / 255, alpha: 1)
        }
    )
    static let softIconNeutral = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .tertiarySystemFill }
            return UIColor(red: 237 / 255, green: 236 / 255, blue: 234 / 255, alpha: 1)
        }
    )

    static let incomeSoftBadgeBackground = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .systemGreen.withAlphaComponent(0.28) }
            return UIColor(red: 200 / 255, green: 240 / 255, blue: 216 / 255, alpha: 1)
        }
    )

    /// Неактивные основные кнопки (светлая схема: достаточный контраст с белым текстом)
    static let buttonFillDisabled = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return .tertiarySystemFill }
            return .systemGray3
        }
    )

    /// В Dark у «чёрных» теней нет видимой подложки — используем лёгкое «свечение».
    static let heroPanelShadow = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return UIColor(white: 1, alpha: 0.14) }
            return UIColor(white: 0, alpha: 0.08)
        }
    )

    static let groupedRowShadow = Color(
        UIColor { tc in
            if tc.userInterfaceStyle == .dark { return UIColor(white: 1, alpha: 0.16) }
            return UIColor(white: 0, alpha: 0.06)
        }
    )
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
            .shadow(color: FamilyAppStyle.heroPanelShadow, radius: 12, x: 0, y: 2)
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
            color: isSingle ? FamilyAppStyle.groupedRowShadow : .clear,
            radius: 8,
            x: 0,
            y: 2
        )
    }
}
