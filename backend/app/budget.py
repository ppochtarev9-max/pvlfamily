from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from . import models, schemas
from .database import get_db

router = APIRouter()

# --- КАТЕГОРИИ ---
# Сначала списки и создание (без ID)
@router.get("/categories", response_model=List[schemas.CategoryOut])
def get_categories(db: Session = Depends(get_db)):
    return db.query(models.Category).all()

@router.post("/categories", response_model=schemas.CategoryOut, status_code=201) # Без слэша
def create_category(cat: schemas.CategoryCreate, db: Session = Depends(get_db)):
    if cat.parent_id:
        parent = db.get(models.Category, cat.parent_id)
        if parent: cat.type = parent.type
    db_cat = models.Category(name=cat.name, type=cat.type, parent_id=cat.parent_id)
    db.add(db_cat)
    db.commit()
    db.refresh(db_cat)
    return db_cat

# Потом операции с ID
@router.put("/categories/{cat_id}", response_model=schemas.CategoryOut)
def update_category(cat_id: int, cat_in: schemas.CategoryCreate, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj: raise HTTPException(404, "Not found")
    # ... обновление ...
    db.commit()
    db.refresh(obj)
    return obj

@router.delete("/categories/{cat_id}")
def delete_category(cat_id: int, db: Session = Depends(get_db)):
    # ... удаление ...
    return {"status": "deleted"}

# --- ТРАНЗАКЦИИ ---
# Сначала списки и создание
@router.get("/transactions", response_model=List[schemas.TransactionOut])
def get_transactions(db: Session = Depends(get_db)):
    txs = db.query(models.Transaction).order_by(models.Transaction.date.desc()).all()
    return [make_tx_resp(t) for t in txs]

@router.post("/transactions", response_model=schemas.TransactionOut, status_code=201) # Без слэша
def create_transaction(tx: schemas.TransactionCreate, db: Session = Depends(get_db)):
    user = db.query(models.User).first()
    db_tx = models.Transaction(
        amount=tx.amount, transaction_type=tx.transaction_type,
        category_id=tx.category_id, description=tx.description,
        date=tx.date, created_by_user_id=user.id if user else None
    )
    db.add(db_tx)
    db.commit()
    db.refresh(db_tx)
    return make_tx_resp(db_tx)

# Потом операции с ID
@router.get("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def get_transaction(tx_id: int, db: Session = Depends(get_db)):
    t = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not t: raise HTTPException(404, "Not found")
    return make_tx_resp(t)

@router.put("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def update_transaction(tx_id: int, tx: schemas.TransactionUpdate, db: Session = Depends(get_db)):
    # ...
    pass

@router.delete("/transactions/{tx_id}")
def delete_transaction(tx_id: int, db: Session = Depends(get_db)):
    # ...
    pass

# Хелпер для форматирования
def make_tx_resp(t):
    path = t.category.name if t.category else "No Cat"
    if t.category and t.category.parent:
        path = f"{t.category.parent.name} / {t.category.name}"
    date_str = t.date.strftime("%Y-%m-%dT%H:%M:%S") if isinstance(t.date, datetime) else str(t.date)
    return schemas.TransactionOut(
        id=t.id, amount=t.amount, transaction_type=t.transaction_type,
        category_id=t.category_id, description=t.description,
        date=date_str, creator_name=t.creator.name if t.creator else None,
        category_name=path
    )