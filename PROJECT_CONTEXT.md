# PVLFamily — Контекст проекта

## Назначение

Семейное приложение для учета сна/событий и бюджета:

- iOS-клиент (SwiftUI)
- backend API (FastAPI)
- выгрузки данных в Excel

## Окружение разработки (актуально на 2026-04-23)

- OS: macOS (Darwin 25.4.0, ARM64)
- Xcode: 26.4, Swift 6.3
- Python: 3.12.x (локально), проектный venv в `backend/venv`
- Backend stack: FastAPI, Uvicorn, SQLAlchemy, openpyxl, slowapi
- Режимы API: Local `http://127.0.0.1:8000` / Cloud `https://pvlfamily.ru`

## Архитектура

### iOS (SwiftUI)

- Точки входа: `iOS/PVLFamily/PVLFamilyApp.swift`, `iOS/PVLFamily/MainTabView.swift`
- Ключевые экраны: `DashboardView.swift`, `BudgetView.swift`, `CalendarView.swift`, `ProfileView.swift`
- Сетевой слой и сессия: `iOS/PVLFamily/AuthManager.swift`
- Live Activity: `iOS/PVLFamilyActivity/*`

### Backend (FastAPI)

- Точка входа: `backend/app/main.py`
- Модули:
  - `auth.py` — логин/пользователи/JWT
  - `tracker.py` — логи сна/кормления, статус, статистика, Excel export
  - `budget.py` — категории, транзакции, Excel export
  - `calendar.py` — календарные события
  - `stats.py` — сводные бюджетные метрики
- Модели/схемы: `backend/app/models.py`, `backend/app/schemas.py`
- Тесты: `backend/tests/` (pytest)

## Текущий API-контракт (важное)

- Budget в `main` работает через `groups/subcategories` (без legacy `categories`).
- Экспорт данных:
  - `GET /budget/export/excel`
  - `GET /tracker/export/excel`
- Для экспорта обязательны:
  - авторизация (Bearer token)
  - фильтры `start_date` и `end_date`
  - корректные имена файлов формата `{type}_export_{YYYYMMDD_HHMMSS}.xlsx`

## Запуск и проверка

- Backend dev:
  - `cd backend && source venv/bin/activate && uvicorn app.main:app --reload`
- Backend tests:
  - `cd /Users/Pavel/PVLFamily`
  - `./backend/venv/bin/python -m pytest backend/tests`
- Точечные тесты:
  - `./backend/venv/bin/python -m pytest backend/tests/test_budget.py backend/tests/test_tracker.py`

## Соглашения по репозиторию

- Не коммитить локальные Xcode UI-состояния:
  - `*.xcuserstate`
  - `iOS/**/*.xcuserdatad/`
- Перед крупными изменениями работать в отдельной ветке.
- Для feature-изменений проверять совместимость библиотек с текущим окружением (особенно `openpyxl`).

## Известные проблемы и техдолг

- Live Activity timer обновляется нестабильно (виджет может "замирать").
- Есть риск рассинхронизации контракта между backend и iOS при изменении модели категорий бюджета.
- Нужны дополнительные unit-тесты в iOS (сейчас основной фокус на UI tests).

## Где смотреть детали

- Стратегические задачи: `BACKLOG.md`
- История решений/инцидентов: `DEV_LOG.md`

