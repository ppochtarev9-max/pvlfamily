from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from typing import List
from jose import jwt

from . import models, schemas
from .database import get_db

router = APIRouter()
SECRET_KEY = "simple-family-secret-key-change-later"

def get_current_user_id(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Token missing")
    
    # Ожидаем формат "Bearer <token>"
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authentication scheme")
        
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        return int(payload.get("sub"))
    except:
        raise HTTPException(status_code=401, detail="Invalid token")
        
@router.get("/events", response_model=List[schemas.EventResponse])
def get_events(db: Session = Depends(get_db)):
    return db.query(models.CalendarEvent).order_by(models.CalendarEvent.event_date).all()

@router.post("/events", response_model=schemas.EventResponse)
def create_event(event: schemas.EventCreate, db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)):
    db_event = models.CalendarEvent(
        title=event.title,
        event_type=event.event_type,
        event_date=event.event_date,
        description=event.description,
        created_by_user_id=user_id
    )
    db.add(db_event)
    db.commit()
    db.refresh(db_event)
    return db_event
