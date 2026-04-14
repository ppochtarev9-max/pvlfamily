from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from . import models
from .database import engine, SessionLocal  # <--- Добавили SessionLocal
from .auth import router as auth_router
from .budget import router as budget_router
from .calendar import router as calendar_router
from .stats import router as stats_router
from .tracker import router as tracker_router
import logging

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PVLFamily")

# Создаем таблицы (если их нет)
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="PVLFamily API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/auth", tags=["Auth"])
app.include_router(budget_router, prefix="/budget", tags=["Budget"])
app.include_router(calendar_router, prefix="/calendar", tags=["Calendar"])
app.include_router(stats_router, prefix="/dashboard", tags=["Dashboard"])
app.include_router(tracker_router, prefix="/tracker", tags=["Tracker"])

@app.get("/health")
def health():
    return {"status": "ok", "message": "Backend is running"}

def cleanup_test_data():
    """Очищает тестовых пользователей и их данные при старте сервера."""
    logger.info("🧹 Начало очистки тестовых данных...")
    db = SessionLocal()
    try:
        # Префиксы тестовых пользователей
        test_prefixes = ["UITest_", "User_", "Feed_", "Timer_", "Long_", "Net_", "Nav_"]
        
        # Получаем всех пользователей
        all_users = db.query(models.User).all()
        deleted_count = 0
        
        for user in all_users:
            # Проверяем имя на совпадение с префиксами
            if any(user.name.startswith(prefix) for prefix in test_prefixes):
                user_id = user.id
                
                # Удаляем связанные данные (каскад может не сработать явно во всех БД)
                db.query(models.BabyLog).filter(models.BabyLog.user_id == user_id).delete()
                db.query(models.Transaction).filter(models.Transaction.user_id == user_id).delete()
                db.query(models.CalendarEvent).filter(models.CalendarEvent.user_id == user_id).delete()
                
                # Удаляем самого пользователя
                db.delete(user)
                deleted_count += 1
                logger.info(f"   🗑 Удален тестовый пользователь: {user.name} (ID: {user_id})")
        
        db.commit()
        logger.info(f"✅ Очистка завершена. Удалено записей: {deleted_count}")
        
    except Exception as e:
        db.rollback()
        logger.error(f"❌ Ошибка при очистке тестовых данных: {e}")
    finally:
        db.close()

# Запускаем очистку при старте приложения
cleanup_test_data()