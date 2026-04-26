import Foundation

/// Rule-based «рекомендации» по сну (заготовка под ИИ).
enum TrackerSleepInsightBuilder {
    static func todayLine(sleepMinutes: Int, sessions: Int) -> String {
        if sleepMinutes == 0 {
            return "За сегодня ещё нет завершённых снов — данные появятся после окончания сна."
        }
        if sleepMinutes < 3 * 60 {
            return "Сон за день короткий — стоит проверить дневник и дозировку бодрствования."
        }
        if sleepMinutes > 6 * 60, sessions == 1 {
            return "Длинные непрерывные сны — тренд для возраста может быть в норме, следи за дневным сном."
        }
        if sessions > 3 {
            return "Много коротких снов — типично для малыша; важна суммарная длина за день."
        }
        return "Сон за день в пределах ожидаемого; при сомнениях сверяйс с педиатром."
    }

    static func monthLine(totalMinutes: Int, daysWithData: Int, averagePerSession: Int) -> String {
        if totalMinutes == 0 {
            return "В этом месяце ещё нет завершённых эпизодов сна в базе."
        }
        if daysWithData < 3 {
            return "Мало дней с данными — картина прояснится, когда накопится больше ночей."
        }
        let avg = totalMinutes / max(1, daysWithData)
        if avg < 3 * 60 {
            return "Средняя суточная длина сна заметно ниже типичного диапазона — посмотри тренд по неделям."
        }
        if avg > 5 * 60 * 2 {
            return "Суммарный сон за сутки высокий — сравни с прошлой неделей в отчёте «неделя к неделе»."
        }
        if averagePerSession > 0, averagePerSession < 40 {
            return "Много коротких эпизодов; средний сон за эпизод невысокий — пригодится сравнение с прошлым месяцем."
        }
        return "Режим сна в этом месяце можно сопоставить с прошлой неделей и выбросами в списке дней."
    }
}
