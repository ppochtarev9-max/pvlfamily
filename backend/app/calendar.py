from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from . import models, schemas
from .database import get_db
from datetime import datetime

router = APIRouter()

@router.get("/events", response_model=List[schemas.EventResponse])
def get_events(db: Session = Depends(get_db)):
    return db.query(models.CalendarEvent).order_by(models.CalendarEvent.event_date.desc()).all()

@router.post("/events", response_model=schemas.EventResponse)
def create_event(event: schemas.EventCreate, db: Session = Depends(get_db)):
    # Создаем событие БЕЗ created_by_user_id, так как в модели этого поля нет
    db_event = models.CalendarEvent(
        title=event.title,
        description=event.description,
        event_date=event.event_date,
        event_type=event.event_type,
        user_id=None # Можно привязать к пользователю позже, если добавить поле в модель
    )
    db.add(db_event)
    db.commit()
    db.refresh(db_event)
    return db_event

@router.delete("/events/{event_id}")
def delete_event(event_id: int, db: Session = Depends(get_db)):
    db_event = db.query(models.CalendarEvent).filter(models.CalendarEvent.id == event_id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Event not found")
    db.delete(db_event)
    db.commit()
    return {"status": "deleted"}
