from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from .database import get_db
from .models import BabyLog, User
from .schemas import BabyLogCreate, BabyLogOut, BabyLogUpdate
from .auth import get_current_user

router = APIRouter()

@router.get("/logs", response_model=List[BabyLogOut])
def get_logs(
    skip: int = 0, 
    limit: int = 50, 
    event_type: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(BabyLog).filter(BabyLog.user_id == current_user.id)
    
    if event_type:
        query = query.filter(BabyLog.event_type == event_type)
        
    # Сортировка: новые сверху
    logs = query.order_by(BabyLog.start_time.desc()).offset(skip).limit(limit).all()
    
    # Добавляем имена создателей вручную для ответа
    result = []
    for log in logs:
        log_dict = BabyLogOut.from_orm(log)
        # Исправление: Используем сохраненное имя (snapshot) или заглушку
        log_dict.creator_name = log.creator_name_snapshot if log.creator_name_snapshot else "Пользователь (удален)"
        result.append(log_dict)
        
    return result

@router.post("/logs", response_model=BabyLogOut)
def create_log(
    log_in: BabyLogCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Авто-расчет длительности, если указано end_time
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
        creator_name_snapshot=current_user.name  # СОХРАНЯЕМ ИМЯ ПОЛЬЗОВАТЕЛЯ
    )
    
    db.add(db_log)
    db.commit()
    db.refresh(db_log)
    
    # Добавляем имя для ответа
    res = BabyLogOut.from_orm(db_log)
    res.creator_name = db_log.creator_name_snapshot if db_log.creator_name_snapshot else "Пользователь (удален)"
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
    
    # Пересчет длительности при обновлении end_time
    if db_log.start_time and db_log.end_time:
        delta = db_log.end_time - db_log.start_time
        db_log.duration_minutes = int(delta.total_seconds() / 60)
        
    db.commit()
    db.refresh(db_log)
    
    # Добавляем имя для ответа
    res = BabyLogOut.from_orm(db_log)
    res.creator_name = db_log.creator_name_snapshot if db_log.creator_name_snapshot else "Пользователь (удален)"
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