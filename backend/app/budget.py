from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from jose import jwt
from datetime import datetime

from . import models, schemas
from .database import get_db

router = APIRouter()
SECRET_KEY = "simple-family-secret-key-change-later"

def get_current_user_id(x_auth_token: str = Header(None, alias="Authorization")):
    # Если токен приходит в формате "Bearer <токен>", нужно убрать префикс
    if x_auth_token and x_auth_token.startswith("Bearer "):
        x_auth_token = x_auth_token[7:]
    
    if not x_auth_token:
        raise HTTPException(status_code=401, detail="Token missing")

    try:
        payload = jwt.decode(x_auth_token, SECRET_KEY, algorithms=["HS256"])
        return int(payload.get("sub"))
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

# --- CATEGORIES ---

@router.get("/categories", response_model=List[schemas.CategoryResponse])
def get_categories(db: Session = Depends(get_db)):
    # Получаем только корневые категории (у которых нет родителя)
    roots = db.query(models.Category).filter(models.Category.parent_id == None).all()
    
    # Рекурсивная функция для построения дерева
    def build_tree(category):
        # Создаем ответ без детей сначала
        data = schemas.CategoryResponse(
            id=category.id,
            name=category.name,
            type=category.type,
            parent_id=category.parent_id,
            children=[]
        )
        # Рекурсивно добавляем детей
        for child in category.children:
            data.children.append(build_tree(child))
        return data

    return [build_tree(cat) for cat in roots]

@router.post("/categories", response_model=schemas.CategoryResponse)
def create_category(category: schemas.CategoryCreate, db: Session = Depends(get_db)):
    if category.parent_id:
        parent = db.query(models.Category).filter(models.Category.id == category.parent_id).first()
        if not parent:
            raise HTTPException(status_code=400, detail="Parent not found")
        if parent.type != category.type:
            raise HTTPException(status_code=400, detail="Type mismatch with parent")

    db_cat = models.Category(**category.dict())
    db.add(db_cat)
    db.commit()
    db.refresh(db_cat)
    
    return schemas.CategoryResponse(id=db_cat.id, name=db_cat.name, type=db_cat.type, parent_id=db_cat.parent_id, children=[])

@router.put("/categories/{c_id}", response_model=schemas.CategoryResponse)
def update_category(c_id: int, category: schemas.CategoryUpdate, db: Session = Depends(get_db)):
    db_cat = db.query(models.Category).filter(models.Category.id == c_id).first()
    if not db_cat:
        raise HTTPException(status_code=404, detail="Category not found")
    
    update_data = category.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_cat, key, value)
        
    db.commit()
    db.refresh(db_cat)
    # Возвращаем обновленный объект (без перестроения дерева для простоты, фронт сам обновит)
    return schemas.CategoryResponse(id=db_cat.id, name=db_cat.name, type=db_cat.type, parent_id=db_cat.parent_id, children=[])

@router.delete("/categories/{c_id}")
def delete_category(c_id: int, db: Session = Depends(get_db)):
    db_cat = db.query(models.Category).filter(models.Category.id == c_id).first()
    if not db_cat:
        raise HTTPException(status_code=404, detail="Not found")
    
    # Проверка: если есть дети, удалять нельзя (или нужно удалять рекурсивно, но пока запретим)
    if db_cat.children:
        raise HTTPException(status_code=400, detail="Cannot delete category with subcategories")
        
    db.delete(db_cat)
    db.commit()
    return {"status": "ok"}

# --- TRANSACTIONS ---

@router.get("/transactions", response_model=List[schemas.TransactionResponse])
def get_transactions(db: Session = Depends(get_db)):
    # Явно указываем подгрузку связей category и creator
    query = db.query(models.Transaction).options(
        joinedload(models.Transaction.category),
        joinedload(models.Transaction.creator)
    ).order_by(models.Transaction.date.desc())
    
    txs = query.all()
    
    result = []
    for tx in txs:
        # Принудительно получаем имена, проверяя наличие объектов
        c_name = tx.category.name if tx.category else "Без категории"
        u_name = tx.creator.name if tx.creator else "Unknown"
        
        # Отладочный принт в консоль сервера (чтобы ты видел, что там реально)
        print(f"DEBUG: Tx ID {tx.id} | User ID {tx.created_by_user_id} | Creator Obj: {tx.creator} | Name: {u_name}")

        result.append(schemas.TransactionResponse(
            id=tx.id,
            amount=tx.amount,
            transaction_type=tx.transaction_type,
            category_id=tx.category_id,
            description=tx.description,
            date=tx.date,
            created_by_user_id=tx.created_by_user_id,
            creator_name=u_name,
            category_name=c_name
        ))
    return result
        
@router.post("/transactions", response_model=schemas.TransactionResponse)
def create_transaction(transaction: schemas.TransactionCreate, db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)):
    if not transaction.date:
        transaction.date = datetime.utcnow()
        
    db_tx = models.Transaction(**transaction.dict(), created_by_user_id=user_id)
    db.add(db_tx)
    db.commit()
    db.refresh(db_tx)
    
    # Явно запрашиваем связанные объекты, чтобы убедиться в их наличии
    cat = db.query(models.Category).filter(models.Category.id == db_tx.category_id).first()
    user = db.query(models.User).filter(models.User.id == user_id).first()
    
    return schemas.TransactionResponse(
        id=db_tx.id,
        amount=db_tx.amount,
        transaction_type=db_tx.transaction_type,
        category_id=db_tx.category_id,
        description=db_tx.description,
        date=db_tx.date,
        created_by_user_id=db_tx.created_by_user_id,
        creator_name=user.name if user else "Unknown", # Должно сработать
        category_name=cat.name if cat else "Unknown"
    )

@router.put("/transactions/{t_id}", response_model=schemas.TransactionResponse)
def update_transaction(t_id: int, transaction: schemas.TransactionUpdate, db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)):
    db_tx = db.query(models.Transaction).filter(models.Transaction.id == t_id).first()
    if not db_tx:
        raise HTTPException(status_code=404, detail="Not found")
    
    update_data = transaction.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_tx, key, value)
        
    db.commit()
    db.refresh(db_tx)
    
    cat = db.query(models.Category).filter(models.Category.id == db_tx.category_id).first()
    user = db.query(models.User).filter(models.User.id == db_tx.created_by_user_id).first()
    
    return schemas.TransactionResponse(
        id=db_tx.id, amount=db_tx.amount, transaction_type=db_tx.transaction_type,
        category_id=db_tx.category_id, description=db_tx.description, date=db_tx.date,
        created_by_user_id=db_tx.created_by_user_id,
        creator_name=user.name if user else "Unknown",
        category_name=cat.name if cat else "Unknown"
    )

@router.delete("/transactions/{t_id}")
def delete_transaction(t_id: int, db: Session = Depends(get_db)):
    db_tx = db.query(models.Transaction).filter(models.Transaction.id == t_id).first()
    if not db_tx:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(db_tx)
    db.commit()
    return {"status": "ok"}