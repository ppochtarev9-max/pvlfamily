from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from jose import jwt
from datetime import datetime, timedelta

from . import models, schemas
from .database import get_db

router = APIRouter()
SECRET_KEY = "simple-family-secret-key-change-later"
ALGORITHM = "HS256"

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=30)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

@router.post("/login")
def login(user_data: schemas.UserCreate, db: Session = Depends(get_db)):
    if not user_data.name or len(user_data.name.strip()) == 0: # <-- Тут тоже было user_data
        raise HTTPException(status_code=400, detail="Имя не может быть пустым")
    
    user = db.query(models.User).filter(models.User.name == user_data.name).first()
    
    if not user:
        user = models.User(name=user_data.name)
        db.add(user)
        db.commit()
        db.refresh(user)
    
    token = create_access_token(data={"sub": str(user.id)})
    return {"access_token": token, "token_type": "bearer", "user_id": user.id, "name": user.name}

@router.get("/users", response_model=List[schemas.UserOut])
def get_users(db: Session = Depends(get_db)):
    users = db.query(models.User).all()
    return users

# --- Добавлено для защиты эндпоинтов дашборда ---
from fastapi import Header, HTTPException
from jose import JWTError, jwt

def get_current_user(authorization: str = Header(None), db: Session = Depends(get_db)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Token missing")
    
    # Ожидаем формат "Bearer <token>"
    parts = authorization.split()
    if len(parts) != 2 or parts[0] != "Bearer":
        raise HTTPException(status_code=401, detail="Invalid token format")
    
    token = parts[1]
    
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: int = int(payload.get("sub"))
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
    
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    
    return user
