# PVLFamily — Контекст проекта

## Назначение

Семейное приложение для учета сна/событий и бюджета:

- iOS-клиент (SwiftUI)
- backend API (FastAPI)
- выгрузки данных в Excel

## Окружение разработки (актуально на 2026-04-26)

- OS: macOS (Darwin 25.4.0, ARM64)
- Xcode: 26.4, Swift 6.3
- Python: 3.12.x (локально), проектный venv в `backend/venv`
- Backend stack: FastAPI, Uvicorn, SQLAlchemy, openpyxl, slowapi, passlib, python-dotenv
- Режимы API: Local `http://127.0.0.1:8000` / Cloud `https://pvlfamily.ru`

### Снимок: локаль и production (2026-04-26)

- **Репозиторий** `main` синхронизирован локально и на сервере; конфиг **только** `backend/.env` (секреты, `ADMIN_*`, `SECRET_KEY`).
- **Cloud:** приложение в `/home/user1/pvl_app`, venv `backend/venv`, systemd `pvlfamily`, Uvicorn `app.main:app`, БД `backend/pvlfamily.db` (путь фиксирован в `database.py`).
- **Auth:** парольный вход; bootstrap админа из env; в iOS при логине 401 показываем текст с сервера / «неверные данные», а не «сессия истекла».
- **Бюджет / SQLite:** `create_all` **не** обновляет схему существующих таблиц. Если в `categories` нет `group_id`, при старте API выполняется `ensure_budget_schema()` в `main.py` (пересоздание `transactions` / `categories` / `category_groups`). Исторический импорт: `backend/import_history.py` (CSV `;`, владелец транзакций — пользователь с заданным `--user`).
- **UI iOS (Liquid Glass pass):** в `main` влит единый визуальный проход по вкладкам/формам (`FamilyAppStyle.swift`), системный таббар iOS 26 (`TabView` + `sidebarAdaptable`), унификация карточек/фонов/акцентов на экранах `Dashboard/Budget/Calendar(Дневник)/Tracker/Profile` и связанных формах/листах.
- **Git hygiene:** локальные артефакты (`.deriveddata/`, `design-pixso*`) добавлены в `.gitignore`; рабочий `main` после деплоя синхронизирован с `origin/main`.
- **Пагинация API (2026-04-26):** `GET /budget/transactions` → JSON-объект `items` + `has_more` + `total` (не массив с корня); keyset `after_date`+`after_id`, глобальный `balance` на строке = оконный `SUM` по **всей** таблице `transactions`, лента фильтруется отдельно. `GET /tracker/logs` → `items` + `has_more` + `total`, keyset `after_start_time`+`after_id`. Клиент iOS: догрузка внизу списка; выбор «Пользователь» в фильтре бюджета влияет на шапку (сводка), не на скрытие чужих операций в ленте.

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
- **Списки с историей:** `GET /budget/transactions` и `GET /tracker/logs` (см. снимок выше) — только с Bearer; пагинация keyset, без выдачи «всей базы» одним ответом.
- Экспорт данных:
  - `GET /budget/export/excel`
  - `GET /tracker/export/excel`
- Для экспорта обязательны:
  - авторизация (Bearer token)
  - фильтры `start_date` и `end_date`
  - корректные имена файлов формата `{type}_export_{YYYYMMDD_HHMMSS}.xlsx`

## Исторические данные
- История транзакций может загружаться скриптом `backend/import_history.py`.
- Перед изменениями модели бюджета/категорий обязательно проверять совместимость импорта.
- При изменении логики категорий отдельно прогонять тест/проверку импорт-скрипта на локальной БД.

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

## Правила работы (обязательно)
- Ничего не менять без четкого плана (scope, риски, проверка, откат).
- Любая реализация должна сохранять текущую рабочую функциональность (no regressions).
- Для backend и iOS добавлять достаточно комментариев и диагностических `print`/логов в новых/сложных местах.
- Для нового модуля/фичи сразу добавлять автотесты.
- Ничего не удалять без явного подтверждения.
- БД не чистить без явного указания.
- После каждого запроса/фичи обновлять `DEV_LOG.md`.
- Для спорных UX/поведенческих решений сначала согласовывать с пользователем.

## Известные проблемы и техдолг

- Live Activity: таймер сна/бодрствования использует `Text(startTime, style: .timer)` в extension и в `TrackerStatusWidget` (секунда в секунду без фонового `Timer` в приложении). Синхронизация с API: `syncWithStatus` в `DashboardView` — разбор ISO через `TrackerAPIDate.parse`, якорь бодрствования = `last_wake_up` (конец последнего сна); при ошибке разбора не подставлять `Date()`.
- Демо-данные трекера: `backend/seed_tracker_demo.py` (сброс `baby_logs` + 50–60 записей). Деплой на cloud: `deploy_cloud.sh` из корня, переменные в `.env_commands`.
- Есть риск рассинхронизации контракта между backend и iOS при изменении модели категорий бюджета.
- Нужны дополнительные unit-тесты в iOS (сейчас основной фокус на UI tests).

## Где смотреть детали

- Стратегические задачи: `BACKLOG.md`
- История решений/инцидентов: `DEV_LOG.md`
- Рабочий стандарт процесса: `DEVELOPMENT_RULES.md`

