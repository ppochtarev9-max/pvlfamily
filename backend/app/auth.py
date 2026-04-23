import os
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException, Header, Request
from sqlalchemy.orm import Session
from typing import List
from jose import jwt, JWTError
from datetime import datetime, timedelta, timezone
from slowapi import Limiter
from slowapi.util import get_remote_address

from . import models, schemas
from .database import get_db

# Загрузка переменных окружения
load_dotenv()

router = APIRouter()

# Инициализация лимитера (должен быть тем же экземпляром, что и в main.py, 
# но для простоты создаем здесь новый с той же логикой)
limiter = Limiter(key_func=get_remote_address)

# Чтение SECRET_KEY из переменной окружения
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_DAYS = int(os.getenv("ACCESS_TOKEN_EXPIRE_DAYS", "30"))

if not SECRET_KEY:
    raise ValueError("КРИТИЧЕСКАЯ ОШИБКА: Не найден SECRET_KEY в переменных окружения. Создайте файл .env")

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

@router.post("/login")
@limiter.limit("5/minute")  # Защита: макс 5 попыток входа в минуту с одного IP
def login(request: Request, user_data: schemas.UserCreate, db: Session = Depends(get_db)):
    if not user_data.name or len(user_data.name.strip()) == 0:
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

@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    
    db.delete(user)
    db.commit()
    return {"detail": "Пользователь успешно удален"}

def get_current_user(authorization: str = Header(None), db: Session = Depends(get_db)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Token missing")
    
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