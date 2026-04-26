import Foundation

/// Rule-based тексты для блока «вывод» (потом можно заменить на ИИ).
enum BudgetInsightBuilder {
    static func todayLine(balance: Double) -> String {
        if balance >= 0 {
            return "Баланс неотрицательный — запас по деньгам есть."
        }
        return "Баланс отрицательный — стоит присмотреться к тратам."
    }

    static func monthLine(current: MonthlyStats, previous: MonthlyStats?) -> String {
        guard let prev = previous else {
            let inc = Int(current.total_income.rounded())
            let exp = Int(abs(current.total_expense).rounded())
            return "За месяц: доходы ≈ \(inc) ₽, расходы ≈ \(exp) ₽."
        }
        let curExp = abs(current.total_expense)
        let prevExp = abs(prev.total_expense)
        if curExp < prevExp * 0.95 {
            return "Расходы ниже прошлого месяца — тренд спокойный."
        }
        if curExp > prevExp * 1.05 {
            return "Расходы выше прошлого месяца — держи в уме."
        }
        return "Расходы примерно как в прошлом месяце."
    }
}
