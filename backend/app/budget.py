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
        
@router.get("/transactions", response_model=List[schemas.TransactionResponse])
def get_transactions(db: Session = Depends(get_db)):
    transactions = db.query(models.Transaction).order_by(models.Transaction.date.desc()).all()
    
    # Формируем ответ вручную, чтобы добавить имена категорий плоскими полями
    result = []
    for t in transactions:
        result.append({
            "id": t.id,
            "amount": t.amount,
            "description": t.description,
            "date": t.date,
            "category_id": t.category_id,
            "category_name": t.category.name if t.category else "Unknown",
            "category_type": t.category.type if t.category else "expense"
        })
    return result

@router.post("/transactions", response_model=schemas.TransactionResponse)
def create_transaction(transaction: schemas.TransactionCreate, db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)):
    # Проверка категории
    category = db.query(models.Category).filter(models.Category.id == transaction.category_id).first()
    if not category:
        raise HTTPException(status_code=400, detail="Category not found")

    db_transaction = models.Transaction(
        amount=transaction.amount,
        category_id=transaction.category_id,
        description=transaction.description,
        created_by_user_id=user_id
    )
    db.add(db_transaction)
    db.commit()
    db.refresh(db_transaction)
    
    # Возвращаем с именами категорий
    return {
        "id": db_transaction.id,
        "amount": db_transaction.amount,
        "description": db_transaction.description,
        "date": db_transaction.date,
        "category_id": db_transaction.category_id,
        "category_name": category.name,
        "category_type": category.type
    }

@router.get("/categories", response_model=List[schemas.CategoryResponse])
def get_categories(db: Session = Depends(get_db)):
    cats = db.query(models.Category).all()
    if not cats:
        defaults = [
            {"name": "Продукты", "type": "expense"}, 
            {"name": "Жилье", "type": "expense"},
            {"name": "Транспорт", "type": "expense"}, 
            {"name": "Развлечения", "type": "expense"},
            {"name": "Зарплата", "type": "income"}, 
            {"name": "Подработка", "type": "income"}
        ]
        for d in defaults:
            cat = models.Category(name=d["name"], type=d["type"])
            db.add(cat)
        db.commit()
        return db.query(models.Category).all()
    return cats
