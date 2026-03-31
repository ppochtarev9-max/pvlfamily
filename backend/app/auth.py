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
