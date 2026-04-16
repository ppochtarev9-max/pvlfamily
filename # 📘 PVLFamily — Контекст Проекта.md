# 📘 PVLFamily — Контекст Проекта

## 🖥 Окружение разработки
- **OS:** macOS 26.4.1 (Darwin 25.4.0, ARM64)
- **Xcode:** 26.4 (Build 17E192)
- **Swift:** 6.3
- **Симулятор:** iPhone 17 Pro (iOS 26.4)
- **Python:** 3.12.13 (Homebrew)
- **Backend:** FastAPI 0.104.1, Uvicorn 0.24.0, SQLAlchemy 2.0.23
- **Режимы работы:** Local (http://127.0.0.1:8000) / Cloud (pvlfamily.ru)

## 🏗 Архитектура
### iOS (SwiftUI)
- **Точки входа:** `PVLFamilyApp.swift`, `MainTabView.swift`
- **Ключевые экраны:** `DashboardView.swift` (трекер сна), `BudgetView.swift`, `CalendarView.swift`
- **Live Activity:** `PVLFamilyActivity.swift` (виджет), `SleepActivityAttributes.swift` (модель)
- **Сервисы:** `AuthManager.swift` (авторизация), `NotificationManager.swift`

### Backend (FastAPI)
- **База данных:** SQLite (`backend/pvlfamily.db`), переход на PostgreSQL в облаке
- **Модули:** `auth.py`, `tracker.py`, `budget.py`, `calendar.py`, `stats.py`
- **Тесты:** `backend/tests/` (pytest)

## 🔄 Процесс разработки
1. **Правило:** "Не ломать то, что работает!"
2. **Коммиты:** Автосохранение через `update_readme.py` перед деплоем.
3. **Деплой:** Скрипт пушит в GitHub → обновляет сервер на cloud.ru.
4. **Формат кода:** Полные файлы вместо фрагментов.

## ⚠️ Текущие проблемы
1. **Live Activity Timer:** Виджет замирает, обновляется только при сворачивании/разблокировке.
   - *Статус:* В работе. Добавлено поле `lastUpdated` в модель, но виджет всё ещё не тикает.
   - *Гипотеза:* Система кэширует состояние, если не меняются ключевые поля, или `.activityPeriodicUpdate` конфликтует с модификаторами.

## 📂 Структура файлов
./iOS/PVLFamily/       — Исходный код приложения
./iOS/PVLFamilyActivity/ — Расширение виджета
./backend/app/         — Бэкенд (API, БД)
./backend/tests/       — Тесты
