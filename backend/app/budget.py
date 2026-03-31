from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from . import models, schemas
from .database import get_db

router = APIRouter()

# --- КАТЕГОРИИ ---

@router.get("/categories", response_model=List[schemas.CategoryOut])
def get_categories(db: Session = Depends(get_db)):
    # Возвращаем ВСЕ категории плоским списком
    return db.query(models.Category).all()

@router.post("/categories/", response_model=schemas.CategoryOut)
def create_category(cat: schemas.CategoryCreate, db: Session = Depends(get_db)):
    # Проверка: если это подкатегория, тип должен совпадать с родителем (опционально, но полезно)
    if cat.parent_id:
        parent = db.get(models.Category, cat.parent_id)
        if parent and parent.type != cat.type:
            # Принудительно ставим тип родителя для подкатегории, чтобы не было путаницы
            cat.type = parent.type
            
    db_cat = models.Category(**cat.dict())
    db.add(db_cat)
    db.commit()
    db.refresh(db_cat)
    return db_cat

@router.delete("/categories/{cat_id}")
def delete_category(cat_id: int, db: Session = Depends(get_db)):
    cat = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")
    
    ids_to_delete = [cat_id]
    def find_children(pid):
        children = db.query(models.Category).filter(models.Category.parent_id == pid).all()
        for c in children:
            ids_to_delete.append(c.id)
            find_children(c.id)
    find_children(cat_id)
    
    # Удаляем транзакции
    db.query(models.Transaction).filter(models.Transaction.category_id.in_(ids_to_delete)).delete(synchronize_session=False)
    # Удаляем категории
    db.query(models.Category).filter(models.Category.id.in_(ids_to_delete)).delete(synchronize_session=False)
    
    db.commit()
    return {"status": "deleted"}

@router.put("/categories/{cat_id}", response_model=schemas.CategoryOut)
def update_category(cat_id: int, cat_in: schemas.CategoryCreate, db: Session = Depends(get_db)):
    db_cat = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not db_cat: raise HTTPException(status_code=404, detail="Not found")
    
    # Если меняем тип у родителя, можно обновить и детей (опционально)
    update_data = cat_in.dict(exclude_unset=True)
    for k, v in update_data.items():
        setattr(db_cat, k, v)
        
    db.commit()
    db.refresh(db_cat)
    return db_cat

# --- ТРАНЗАКЦИИ ---

def format_tx_response(t: models.Transaction) -> schemas.TransactionOut:
    """Хелпер для формирования полного ответа"""
    path = t.category.name if t.category else "Без категории"
    if t.category and t.category.parent:
        path = f"{t.category.parent.name} / {t.category.name}"
        
    return schemas.TransactionOut(
        id=t.id,
        amount=t.amount,
        transaction_type=t.transaction_type,
        category_id=t.category_id,
        description=t.description,
        date=t.date,
        creator_name=t.creator.name if t.creator else None,
        category_name=path
    )

@router.get("/transactions", response_model=List[schemas.TransactionOut])
def get_transactions(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    txs = db.query(models.Transaction).order_by(models.Transaction.date.desc()).offset(skip).limit(limit).all()
    return [format_tx_response(t) for t in txs]

@router.get("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def get_transaction(tx_id: int, db: Session = Depends(get_db)):
    """НОВЫЙ ЭНДПОИНТ: Получение одной транзакции для редактирования"""
    t = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return format_tx_response(t)

@router.post("/transactions/", response_model=schemas.TransactionOut)
def create_transaction(tx: schemas.TransactionCreate, db: Session = Depends(get_db)):
    user = db.query(models.User).first()
    db_tx = models.Transaction(**tx.dict(), created_by_user_id=user.id if user else None)
    db.add(db_tx)
    db.commit()
    db.refresh(db_tx)
    return format_tx_response(db_tx)

@router.put("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def update_transaction(tx_id: int, tx: schemas.TransactionUpdate, db: Session = Depends(get_db)):
    db_tx = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not db_tx: raise HTTPException(status_code=404, detail="Not found")
    
    update_data = tx.dict(exclude_unset=True)
    for k, v in update_data.items():
        setattr(db_tx, k, v)
        
    db.commit()
    db.refresh(db_tx)
    return format_tx_response(db_tx)

@router.delete("/transactions/{tx_id}")
def delete_transaction(tx_id: int, db: Session = Depends(get_db)):
    tx = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not tx: raise HTTPException(status_code=404, detail="Not found")
    db.delete(tx)
    db.commit()
    return {"status": "deleted"}
