from fastapi import APIRouter, Depends, HTTPException, status, Response
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
import time
from . import models, schemas
from .database import get_db

router = APIRouter()

# ==========================================
# КАТЕГОРИИ
# ==========================================

@router.get("/categories", response_model=List[schemas.CategoryOut])
def get_categories(db: Session = Depends(get_db)):
    return db.query(models.Category).all()

# ПУТЬ БЕЗ СЛЭША В КОНЦЕ! И СТРОГО ДО МАРШРУТОВ С {ID}
@router.post("/categories", response_model=schemas.CategoryOut, status_code=201)
def create_category(cat: schemas.CategoryCreate, db: Session = Depends(get_db)):
    if cat.parent_id:
        parent = db.get(models.Category, cat.parent_id)
        if parent:
            cat.type = parent.type
    
    db_cat = models.Category(name=cat.name, type=cat.type, parent_id=cat.parent_id)
    db.add(db_cat)
    db.commit()
    db.refresh(db_cat)
    return db_cat

@router.put("/categories/{cat_id}", response_model=schemas.CategoryOut)
def update_category(cat_id: int, cat_in: schemas.CategoryCreate, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    if cat_in.name:
        obj.name = cat_in.name
    if cat_in.type:
        obj.type = cat_in.type
    if cat_in.parent_id is not None:
        obj.parent_id = cat_in.parent_id
    db.commit()
    db.refresh(obj)
    return obj

@router.delete("/categories/{cat_id}")
def delete_category(cat_id: int, db: Session = Depends(get_db)):
    ids = [cat_id]
    def find_children(pid):
        for c in db.query(models.Category).filter(models.Category.parent_id == pid).all():
            ids.append(c.id)
            find_children(c.id)
    find_children(cat_id)
    
    db.query(models.Transaction).filter(models.Transaction.category_id.in_(ids)).delete(synchronize_session=False)
    db.query(models.Category).filter(models.Category.id.in_(ids)).delete(synchronize_session=False)
    db.commit()
    return {"status": "deleted"}


# ==========================================
# СКРЫТИЕ КАТЕГОРИЙ (РЕКУРСИВНОЕ)
# ==========================================

def get_all_descendants(db: Session, parent_id: int) -> List[int]:
    """Рекурсивно собирает ID всех подкатегорий"""
    ids = []
    children = db.query(models.Category).filter(models.Category.parent_id == parent_id).all()
    for child in children:
        ids.append(child.id)
        ids.extend(get_all_descendants(db, child.id))
    return ids

@router.post("/categories/{cat_id}/hide")
def hide_category(cat_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj: raise HTTPException(404, "Not found")
    
    obj.is_hidden = True
    db.commit()
    
    descendant_ids = get_all_descendants(db, cat_id)
    if descendant_ids:
        db.query(models.Category).filter(models.Category.id.in_(descendant_ids)).update({"is_hidden": True}, synchronize_session=False)
        db.commit()
    return {"status": "hidden"}

@router.post("/categories/{cat_id}/unhide")
def unhide_category(cat_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj: raise HTTPException(404, "Not found")
    
    if obj.parent_id:
        parent = db.get(models.Category, obj.parent_id)
        if parent and parent.is_hidden:
            raise HTTPException(400, detail="Сначала восстановите родителя")
    
    obj.is_hidden = False
    db.commit()
    
    descendant_ids = get_all_descendants(db, cat_id)
    if descendant_ids:
        db.query(models.Category).filter(models.Category.id.in_(descendant_ids)).update({"is_hidden": False}, synchronize_session=False)
        db.commit()
    return {"status": "visible"}

# ==========================================
# ТРАНЗАКЦИИ
# ==========================================

def make_tx_resp(t):
    if not t:
        return None
    path = t.category.name if t.category else "No Cat"
    if t.category and t.category.parent:
        path = f"{t.category.parent.name} / {t.category.name}"
    
    if isinstance(t.date, datetime):
        date_str = t.date.strftime("%Y-%m-%dT%H:%M:%S")
    else:
        date_str = str(t.date)
        
    return schemas.TransactionOut(
        id=t.id, 
        amount=t.amount, 
        transaction_type=t.transaction_type,
        category_id=t.category_id, 
        description=t.description,
        date=date_str,
        creator_name=t.creator.name if t.creator else None,
        category_name=path
    )

# 1. СПИСОК (GET) - без ID
@router.get("/transactions", response_model=List[schemas.TransactionOut])
def get_transactions(response: Response, db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    # 1. Берем ВСЕ транзакции и сортируем ОТ СТАРЫХ К НОВЫМ (как в Excel)
    all_txs = db.query(models.Transaction).order_by(models.Transaction.date.asc()).all()
    
    # 2. Считаем баланс последовательно: Предыдущий + Текущая
    current_balance = 0.0
    calculated_data = []
    
    for t in all_txs:
        # Формула Excel: H_new = H_prev + amount
        # Если расход (-5000), то 100000 + (-5000) = 95000. Верно.
        # Если доход (+1000), то 95000 + 1000 = 96000. Верно.
        current_balance += t.amount
        calculated_data.append({'tx': t, 'balance': current_balance})
    
    # 3. Переворачиваем список обратно (новые сверху), чтобы отдать в UI
    result = []
    for item in reversed(calculated_data):
        resp = make_tx_resp(item['tx'])
        resp.balance = item['balance']
        result.append(resp)
        
    return result

@router.post("/transactions", response_model=schemas.TransactionOut, status_code=201)
def create_transaction(tx: schemas.TransactionCreate, db: Session = Depends(get_db)):
    user = db.query(models.User).first()
    db_tx = models.Transaction(
        amount=tx.amount, 
        transaction_type=tx.transaction_type,
        category_id=tx.category_id, 
        description=tx.description,
        date=tx.date, 
        created_by_user_id=user.id if user else None
    )
    db.add(db_tx)
    db.commit()
    db.refresh(db_tx)
    resp = make_tx_resp(db_tx)
    if resp is None:
        raise HTTPException(status_code=500, detail="Ошибка создания")
    return resp

# 3. МАРШРУТЫ С ID (GET, PUT, DELETE) - ТОЛЬКО ПОСЛЕ POST
@router.get("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def get_transaction(tx_id: int, db: Session = Depends(get_db)):
    t = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Not found")
    return make_tx_resp(t)

@router.put("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def update_transaction(tx_id: int, tx: schemas.TransactionUpdate, db: Session = Depends(get_db)):
    obj = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    
    update_data = tx.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(obj, key, value)
    
    db.commit()
    db.refresh(obj)
    resp = make_tx_resp(obj)
    if resp is None:
        raise HTTPException(status_code=500, detail="Ошибка сериализации")
    return resp

@router.delete("/transactions/{tx_id}")
def delete_transaction(tx_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    
    db.delete(obj)
    db.commit()
    
    # Пауза для гарантии записи на диск
    time.sleep(0.15)
    
    return {"status": "deleted"}






