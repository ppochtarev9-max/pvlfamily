from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone

from .database import get_db
from .models import BabyLog, User
from .schemas import BabyLogCreate, BabyLogOut, BabyLogUpdate
from .auth import get_current_user

router = APIRouter()

def get_utc_now():
    return datetime.now(timezone.utc)

@router.get("/status", response_model=Dict[str, Any])
def get_tracker_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Возвращает текущее состояние трекера для пользователя.
    Формат ответа адаптирован под iOS приложение:
    - is_sleeping: bool
    - current_sleep_id: int (если спит)
    - current_sleep_start: str (ISO8601, если спит)
    - last_wake_up: str (ISO8601, если бодрствует)
    """
    # 1. Ищем активный сон (нет end_time)
    active_sleep = db.query(BabyLog).filter(
        BabyLog.user_id == current_user.id,
        BabyLog.event_type == "sleep",
        BabyLog.end_time == None
    ).first()

    # 2. Ищем последнее завершенное событие сна (для таймера бодрствования)
    last_sleep = db.query(BabyLog).filter(
        BabyLog.user_id == current_user.id,
        BabyLog.event_type == "sleep",
        BabyLog.end_time != None
    ).order_by(BabyLog.end_time.desc()).first()

    last_wake_time = last_sleep.end_time if last_sleep else None

    # 3. Формируем ответ в нужном формате
    if active_sleep:
        return {
            "is_sleeping": True,
            "current_sleep_id": active_sleep.id,       # Важно для кнопки "Завершить"
            "current_sleep_start": active_sleep.start_time.isoformat(),
            "last_wake_up": None
        }
    else:
        return {
            "is_sleeping": False,
            "current_sleep_id": None,
            "current_sleep_start": None,
            "last_wake_up": last_wake_time.isoformat() if last_wake_time else None
        }

@router.get("/logs", response_model=List[BabyLogOut])
def get_logs(
    skip: int = 0, 
    limit: int = 100, 
    event_type: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(BabyLog).filter(BabyLog.user_id == current_user.id)
    
    if event_type:
        query = query.filter(BabyLog.event_type == event_type)
        
    logs = query.order_by(BabyLog.start_time.desc()).offset(skip).limit(limit).all()
    
    result = []
    for log in logs:
        # Вычисляем is_active на лету для списка
        is_active = (log.end_time is None)
        
        log_dict = BabyLogOut.from_orm(log)
        log_dict.creator_name = log.creator_name_snapshot if log.creator_name_snapshot else "Пользователь (удален)"
        log_dict.is_active = is_active
        result.append(log_dict)
        
    return result

@router.post("/logs", response_model=BabyLogOut)
def create_log(
    log_in: BabyLogCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Проверка: нельзя создать новый сон, если уже есть активный
    if log_in.event_type == "sleep":
        existing_active = db.query(BabyLog).filter(
            BabyLog.user_id == current_user.id,
            BabyLog.event_type == "sleep",
            BabyLog.end_time == None
        ).first()
        if existing_active:
            raise HTTPException(status_code=400, detail="Уже идет активный сон. Завершите его сначала.")

    duration = 0
    if log_in.end_time and log_in.start_time:
        delta = log_in.end_time - log_in.start_time
        duration = int(delta.total_seconds() / 60)
    
    db_log = BabyLog(
        user_id=current_user.id,
        event_type=log_in.event_type,
        start_time=log_in.start_time,
        end_time=log_in.end_time,
        duration_minutes=duration,
        note=log_in.note,
        creator_name_snapshot=current_user.name
    )
    
    db.add(db_log)
    db.commit()
    db.refresh(db_log)
    
    res = BabyLogOut.from_orm(db_log)
    res.creator_name = db_log.creator_name_snapshot
    res.is_active = (db_log.end_time is None)
    return res

@router.post("/logs/quick-feed", response_model=BabyLogOut)
def quick_feed(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Быстрое создание записи о кормлении в текущий момент.
    """
    now = get_utc_now()
    db_log = BabyLog(
        user_id=current_user.id,
        event_type="feed",
        start_time=now,
        end_time=now, # Кормление считаем мгновенным событием
        duration_minutes=0,
        note="Быстрое добавление",
        creator_name_snapshot=current_user.name
    )
    
    db.add(db_log)
    db.commit()
    db.refresh(db_log)
    
    res = BabyLogOut.from_orm(db_log)
    res.creator_name = db_log.creator_name_snapshot
    res.is_active = False
    return res

@router.put("/logs/{log_id}", response_model=BabyLogOut)
def update_log(
    log_id: int,
    log_in: BabyLogUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    db_log = db.query(BabyLog).filter(BabyLog.id == log_id, BabyLog.user_id == current_user.id).first()
    if not db_log:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    
    update_data = log_in.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_log, field, value)
    
    # Пересчет длительности с защитой от разных типов дат
    if db_log.start_time and db_log.end_time:
        # Приводим обе даты к timezone-aware, если нужно
        start = db_log.start_time
        end = db_log.end_time
        
        # Если одна из дат naive (без зоны), считаем её UTC
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
            
        delta = end - start
        db_log.duration_minutes = int(delta.total_seconds() / 60)
    elif db_log.end_time is None:
        db_log.duration_minutes = 0        
        
    db.commit()
    db.refresh(db_log)
    
    res = BabyLogOut.from_orm(db_log)
    res.creator_name = db_log.creator_name_snapshot
    res.is_active = (db_log.end_time is None)
    return res

@router.delete("/logs/{log_id}")
def delete_log(
    log_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    db_log = db.query(BabyLog).filter(BabyLog.id == log_id, BabyLog.user_id == current_user.id).first()
    if not db_log:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    
    db.delete(db_log)
    db.commit()
    return {"status": "deleted"}