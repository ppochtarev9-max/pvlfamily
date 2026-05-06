from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from .rate_limit import limiter
from starlette.middleware.base import BaseHTTPMiddleware
import logging
from sqlalchemy import text

# Импорты роутеров
from . import models
from .database import engine, SessionLocal
from .auth import router as auth_router
from .auth import ensure_admin_user
from .budget import router as budget_router
from .calendar import router as calendar_router
from .stats import router as stats_router
from .tracker import router as tracker_router
from .insights import router as insights_router

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PVLFamily")

# Создание таблиц
models.Base.metadata.create_all(bind=engine)

def ensure_budget_schema():
    """
    Миграция SQLite: ранее `categories` могла быть в legacy-схеме без `group_id`.
    `create_all` не добавляет колонки в существующие таблицы — пересоздаём бюджетные таблицы.
    """
    with engine.begin() as conn:
        r = conn.execute(
            text("SELECT 1 FROM sqlite_master WHERE type='table' AND name='categories'")
        )
        if r.fetchone() is None:
            return
        cols = {row[1] for row in conn.execute(text("PRAGMA table_info(categories)"))}
        if "group_id" in cols:
            return
        logger.info(
            "🔄 Схема budget устарела (нет categories.group_id). "
            "Пересоздаём transactions, categories, category_groups."
        )
        conn.execute(text("DROP TABLE IF EXISTS transactions"))
        conn.execute(text("DROP TABLE IF EXISTS categories"))
        conn.execute(text("DROP TABLE IF EXISTS category_groups"))
    models.Base.metadata.create_all(bind=engine)

def ensure_user_auth_columns():
    """
    Легкая миграция для SQLite: добавляем auth-колонки в users, если их еще нет.
    """
    with engine.begin() as conn:
        existing = {row[1] for row in conn.execute(text("PRAGMA table_info(users)"))}
        if "password_hash" not in existing:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_hash VARCHAR"))
        if "is_active" not in existing:
            conn.execute(text("ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT 1"))
        if "is_admin" not in existing:
            conn.execute(text("ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT 0"))
        if "must_reset_password" not in existing:
            conn.execute(text("ALTER TABLE users ADD COLUMN must_reset_password BOOLEAN DEFAULT 0"))

ensure_budget_schema()
ensure_user_auth_columns()

app = FastAPI(title="PVLFamily API")

# --- БЕЗОПАСНОСТЬ: Rate Limiting ---
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# --- БЕЗОПАСНОСТЬ: Заголовки (Security Headers) ---
class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        # Защита от кликтджекинга
        response.headers["X-Frame-Options"] = "DENY"
        # Защита от MIME-sniffing
        response.headers["X-Content-Type-Options"] = "nosniff"
        # Защита от XSS
        response.headers["X-XSS-Protection"] = "1; mode=block"
        # HSTS (только для HTTPS, но добавим для строгости)
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        # Политика контента (базовая)
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        return response

app.add_middleware(SecurityHeadersMiddleware)

# --- БЕЗОПАСНОСТЬ: Ужесточенный CORS ---
# Разрешаем только конкретный домен и локалхост для разработки
allowed_origins = [
    "https://pvlfamily.ru", 
    "http://localhost:8000",
    "http://127.0.0.1:8000"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"], # Явно указываем методы, никаких "*"
    allow_headers=["Authorization", "Content-Type"], # Разрешаем только нужные заголовки
)

# Роутеры
app.include_router(auth_router, prefix="/auth", tags=["Auth"])
app.include_router(budget_router, prefix="/budget", tags=["Budget"])
app.include_router(calendar_router, prefix="/calendar", tags=["Calendar"])
app.include_router(stats_router, prefix="/dashboard", tags=["Dashboard"])
app.include_router(tracker_router, prefix="/tracker", tags=["Tracker"])
app.include_router(insights_router, prefix="/insights", tags=["Insights"])

@app.get("/health")
def health():
    return {"status": "ok", "message": "Backend is running"}

def cleanup_test_data():
    """Очищает тестовые данные при старте приложения."""
    logger.info("🧹 Начало очистки тестовых данных...")
    db = SessionLocal()
    try:
        test_prefixes = ["UITestUser_", "User_", "FeedTestUser_", "FeedTest_", "TimerTestUser_", "TimerBg_", "TimerBgTest_", "LongTimer_", "LongTestUser_", "NetTestUser_", "NavTest_", "NavTestUser_", "NetErr_", "TestUser"]
        
        users_to_delete = []
        for user in db.query(models.User).all():
            if any(user.name.startswith(prefix) for prefix in test_prefixes):
                users_to_delete.append(user.id)
        
        if not users_to_delete:
            logger.info("✅ Тестовые пользователи не найдены.")
            return

        logger.info(f"🗑 Найдено тестовых пользователей: {len(users_to_delete)}")

        if hasattr(models.BabyLog, "user_id"):
            db.query(models.BabyLog).filter(models.BabyLog.user_id.in_(users_to_delete)).delete(synchronize_session=False)
        if hasattr(models.CalendarEvent, "user_id"):
            db.query(models.CalendarEvent).filter(models.CalendarEvent.user_id.in_(users_to_delete)).delete(synchronize_session=False)
        if hasattr(models.Transaction, "user_id"):
            db.query(models.Transaction).filter(models.Transaction.user_id.in_(users_to_delete)).delete(synchronize_session=False)
        if hasattr(models.Category, "user_id"):
            db.query(models.Category).filter(models.Category.user_id.in_(users_to_delete)).delete(synchronize_session=False)

        db.query(models.User).filter(models.User.id.in_(users_to_delete)).delete(synchronize_session=False)
        db.commit()
        logger.info("✅ Очистка завершена.")

    except Exception as e:
        db.rollback()
        logger.error(f"❌ Ошибка при очистке: {e}")
    finally:
        db.close()

cleanup_test_data()

def bootstrap_admin():
    db = SessionLocal()
    try:
        ensure_admin_user(db)
        logger.info("✅ Админ-пользователь синхронизирован из .env")
    except Exception as e:
        logger.error(f"❌ Ошибка bootstrap admin: {e}")
    finally:
        db.close()

bootstrap_admin()