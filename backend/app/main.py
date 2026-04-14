from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
import logging

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

app = FastAPI(title="PVLFamily API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
        test_prefixes = ["UITest_", "User_", "Feed_", "Timer_", "Long_", "Net_", "Nav_"]
        
        # 1. Находим тестовых пользователей
        # Используем getattr для безопасного доступа, если вдруг модель изменится
        users_to_delete = []
        for user in db.query(models.User).all():
            if any(user.name.startswith(prefix) for prefix in test_prefixes):
                users_to_delete.append(user.id)
        
        if not users_to_delete:
            logger.info("✅ Тестовые пользователи не найдены. Очистка завершена.")
            return

        logger.info(f"🗑 Найдено тестовых пользователей: {len(users_to_delete)}")

        # 2. Удаляем связанные данные (каскадно или явно)
        # ВАЖНО: Проверяем наличие атрибута user_id перед использованием, 
        # так как в некоторых моделях связь может быть через category_id
        
        # Трекер (BabyLog) - обычно имеет user_id
        if hasattr(models.BabyLog, "user_id"):
            count = db.query(models.BabyLog).filter(models.BabyLog.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   📝 Удалено записей трекера: {count}")

        # События календаря
        if hasattr(models.CalendarEvent, "user_id"):
            count = db.query(models.CalendarEvent).filter(models.CalendarEvent.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   📅 Удалено событий календаря: {count}")

        # Транзакции - ВНИМАНИЕ! Ошибка была здесь.
        # Если у Transaction нет user_id, проверяем, есть ли связь через категорию.
        # Но проще удалить категории пользователя, а транзакции удалятся каскадом (если настроено),
        # ИЛИ если у транзакции все-таки есть user_id, но мы ошиблись в имени.
        # Для безопасности просто пробуем удалить, если поле есть.
        if hasattr(models.Transaction, "user_id"):
            count = db.query(models.Transaction).filter(models.Transaction.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   💰 Удалено транзакций: {count}")
        else:
            logger.warning("   ⚠️ Модель Transaction не имеет поля user_id. Пропускаем прямое удаление.")
            # Опционально: можно попробовать удалить через join с Category, если связь такая

        # Категории (должны иметь user_id)
        if hasattr(models.Category, "user_id"):
            count = db.query(models.Category).filter(models.Category.user_id.in_(users_to_delete)).delete(synchronize_session=False)
            logger.info(f"   🏷 Удалено категорий: {count}")

        # 3. Удаляем самих пользователей
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