from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
import logging
import os

# Импорты
from . import models
from .database import engine, SessionLocal
from .auth import router as auth_router
from .budget import router as budget_router
from .calendar import router as calendar_router
from .stats import router as stats_router
from .tracker import router as tracker_router

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PVLFamily")

# Создание таблиц
models.Base.metadata.create_all(bind=engine)

# Отключаем стандартную документацию для безопасности на проде
# Документация будет доступна только если явно передать параметр или через отдельный роут (если нужно)
app = FastAPI(
    title="PVLFamily API",
    docs_url=None,  # Скрываем /docs
    redoc_url=None, # Скрываем /redoc
    openapi_url=None if os.getenv("ENVIRONMENT") == "production" else "/openapi.json"
)

# CORS - разрешаем только доверенные домены
allowed_origins = [
    "https://pvlfamily.ru",
    "http://localhost:8000",
    "http://127.0.0.1:8000"
]

# Если не в продакшене, добавляем wildcard для симулятора/теста
if os.getenv("ENVIRONMENT") != "production":
    allowed_origins.append("*")

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Роутеры
app.include_router(auth_router, prefix="/auth", tags=["Auth"])
app.include_router(budget_router, prefix="/budget", tags=["Budget"])
app.include_router(calendar_router, prefix="/calendar", tags=["Calendar"])
app.include_router(stats_router, prefix="/dashboard", tags=["Dashboard"])
app.include_router(tracker_router, prefix="/tracker", tags=["Tracker"])

@app.get("/health")
def health():
    return {"status": "ok", "message": "Backend is running"}

def cleanup_test_data():
    """Очищает тестовые данные при старте приложения."""
    logger.info("🧹 Начало очистки тестовых данных...")
    db = SessionLocal()
    try:
        # Префиксы тестовых пользователей
        test_prefixes = ["UITestUser_", "User_", "FeedTestUser_", "FeedTest_", "TimerTestUser_", "TimerBg_", "TimerBgTest_", "LongTimer_", "LongTestUser_", "NetTestUser_", "NavTest_", "NavTestUser_", "NetErr_"]
        
        users_to_delete = []
        for user in db.query(models.User).all():
            if any(user.name.startswith(prefix) for prefix in test_prefixes):
                users_to_delete.append(user.id)
        
        if not users_to_delete:
            logger.info("✅ Тестовые пользователи не найдены. Очистка завершена.")
            return

        logger.info(f"🗑 Найдено тестовых пользователей: {len(users_to_delete)}")

        if hasattr(models.BabyLog, "user_id"):
            count = db.query(models.BabyLog).filter(models.BabyLog.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   📝 Удалено записей трекера: {count}")

        if hasattr(models.CalendarEvent, "user_id"):
            count = db.query(models.CalendarEvent).filter(models.CalendarEvent.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   📅 Удалено событий календаря: {count}")

        if hasattr(models.Transaction, "user_id"):
            count = db.query(models.Transaction).filter(models.Transaction.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   💰 Удалено транзакций: {count}")
        else:
            logger.warning("   ⚠️ Модель Transaction не имеет поля user_id. Пропускаем прямое удаление.")

        if hasattr(models.Category, "user_id"):
            count = db.query(models.Category).filter(models.Category.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   🏷 Удалено категорий: {count}")

        count = db.query(models.User).filter(models.User.id.in_(users_to_delete)).delete(synchronize_session=False)
        logger.info(f"   👤 Удалено пользователей: {count}")

        db.commit()
        logger.info("✅ Очистка тестовых данных успешно завершена.")

    except Exception as e:
        db.rollback()
        logger.error(f"❌ Ошибка при очистке тестовых данных: {e}")
    finally:
        db.close()

# Запуск очистки при старте
cleanup_test_data()