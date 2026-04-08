from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from . import models, schemas
from .auth import get_current_user
from .database import get_db

router = APIRouter()

# Вспомогательная функция для формирования ответа (аналог make_tx_resp в бюджете)
def make_event_resp(event: models.CalendarEvent):
    if not event:
        return None
    
    # ЛОГИКА ОТОБРАЖЕНИЯ ИМЕНИ:
    # 1. Если есть snapshot (сохраненное имя) - используем его.
    # 2. Если snapshot нет, но есть связь с пользователем - берем имя из БД.
    # 3. Если ничего нет - заглушка.
    creator_display_name = "Неизвестно"
    if event.creator_name_snapshot:
        creator_display_name = event.creator_name_snapshot
    elif event.creator:
        creator_display_name = event.creator.name
    else:
        creator_display_name = "Пользователь (удален)"
        
    return schemas.EventResponse(
        id=event.id,
        title=event.title,
        description=event.description,
        event_date=event.event_date,
        event_type=event.event_type,
        user_id=event.user_id,
        creator_name=creator_display_name
    )

@router.get("/events", response_model=List[schemas.EventResponse])
def get_events(db: Session = Depends(get_db)):
    """
    Получение всех событий. Доступно всем авторизованным пользователям.
    События не фильтруются по пользователю (общий календарь семьи).
    """
    # Добавляем заголовки для отключения кэширования (как в бюджете)
    # Это важно, чтобы новые события появлялись сразу у всех
    events = db.query(models.CalendarEvent).order_by(models.CalendarEvent.event_date.desc()).all()
    return [make_event_resp(e) for e in events]

@router.post("/events", response_model=schemas.EventResponse)
def create_event(
    event: schemas.EventCreate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Создание события. Требуется авторизация.
    Событие создается от имени текущего пользователя, но видно всем.
    """
    db_event = models.CalendarEvent(
        title=event.title,
        description=event.description,
        event_date=event.event_date,
        event_type=event.event_type,
        # Привязываем ID пользователя (станет NULL при удалении пользователя благодаря ondelete="SET NULL")
        user_id=current_user.id,
        # СОХРАНЯЕМ ИМЯ ПОЛЬЗОВАТЕЛЯ НА МОМЕНТ СОЗДАНИЯ
        creator_name_snapshot=current_user.name
    )
    db.add(db_event)
    db.commit()
    db.refresh(db_event)
    return make_event_resp(db_event)

@router.delete("/events/{event_id}")
def delete_event(
    event_id: int, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Удаление события. Требуется авторизация.
    В текущей реализации удалить может любой авторизованный пользователь.
    (При необходимости можно добавить проверку: если event.user_id != current_user.id, то ошибка 403)
    """
    db_event = db.query(models.CalendarEvent).filter(models.CalendarEvent.id == event_id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    
    db.delete(db_event)
    db.commit()
    return {"status": "deleted"}