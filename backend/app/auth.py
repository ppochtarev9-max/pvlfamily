import os
from pathlib import Path
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException, Header, Request
from sqlalchemy.orm import Session
from typing import List
from jose import jwt, JWTError
from datetime import datetime, timedelta, timezone
from slowapi import Limiter
from slowapi.util import get_remote_address
from passlib.context import CryptContext

from . import models, schemas
from .database import get_db

# Загрузка переменных окружения:
# 1) приоритетно backend/.env
# 2) затем системные env (если заданы снаружи)
backend_env_path = Path(__file__).resolve().parents[1] / ".env"
# Только backend/.env; второй load_dotenv() без пути в некоторых окружениях (stdin/heredoc) ломает python-dotenv
load_dotenv(dotenv_path=backend_env_path)

router = APIRouter()

# Инициализация лимитера (должен быть тем же экземпляром, что и в main.py, 
# но для простоты создаем здесь новый с той же логикой)
limiter = Limiter(key_func=get_remote_address)

# Чтение SECRET_KEY из переменной окружения
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_DAYS = int(os.getenv("ACCESS_TOKEN_EXPIRE_DAYS", "30"))
ADMIN_TOKEN = os.getenv("ADMIN_TOKEN")
ADMIN_NAME = os.getenv("ADMIN_NAME", "Паша")
ADMIN_INITIAL_PASSWORD = os.getenv("ADMIN_INITIAL_PASSWORD")
MIN_PASSWORD_LEN = 8

if not SECRET_KEY:
    raise ValueError("КРИТИЧЕСКАЯ ОШИБКА: Не найден SECRET_KEY в переменных окружения. Создайте файл .env")
if not ADMIN_TOKEN:
    raise ValueError("КРИТИЧЕСКАЯ ОШИБКА: Не найден ADMIN_TOKEN в переменных окружения. Создайте файл .env")

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verify_password(plain_password: str, password_hash: str) -> bool:
    if not password_hash:
        return False
    return pwd_context.verify(plain_password, password_hash)

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def validate_password_policy(password: str) -> None:
    if len(password) < MIN_PASSWORD_LEN:
        raise HTTPException(status_code=400, detail=f"Пароль должен быть не короче {MIN_PASSWORD_LEN} символов")

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

@router.post("/login", response_model=schemas.LoginResponse)
@limiter.limit("5/minute")  # Защита: макс 5 попыток входа в минуту с одного IP
def login(request: Request, user_data: schemas.UserLogin, db: Session = Depends(get_db)):
    if not user_data.name or len(user_data.name.strip()) == 0:
        raise HTTPException(status_code=400, detail="Имя не может быть пустым")
    if not user_data.password:
        raise HTTPException(status_code=400, detail="Пароль обязателен")

    user = db.query(models.User).filter(models.User.name == user_data.name.strip()).first()
    if not user or not verify_password(user_data.password, user.password_hash or ""):
        raise HTTPException(status_code=401, detail="Неверные учетные данные")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Пользователь деактивирован")

    token = create_access_token(data={"sub": str(user.id)})
    return {
        "access_token": token,
        "token_type": "bearer",
        "user_id": user.id,
        "name": user.name,
        "force_password_reset": bool(user.must_reset_password),
    }

@router.get("/users", response_model=List[schemas.UserOut])
def get_users(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    users = db.query(models.User).all()
    return users

@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Только админ может удалять пользователей")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    
    db.delete(user)
    db.commit()
    return {"detail": "Пользователь успешно удален"}

@router.post("/admin/users", response_model=schemas.UserOut)
def create_user_by_admin(
    payload: schemas.AdminUserCreate,
    db: Session = Depends(get_db),
    x_admin_token: str = Header(default=None),
):
    if x_admin_token != ADMIN_TOKEN:
        raise HTTPException(status_code=401, detail="Недействительный admin token")
    validate_password_policy(payload.password)

    exists = db.query(models.User).filter(models.User.name == payload.name.strip()).first()
    if exists:
        raise HTTPException(status_code=409, detail="Пользователь уже существует")

    user = models.User(
        name=payload.name.strip(),
        password_hash=hash_password(payload.password),
        is_active=payload.is_active,
        is_admin=False,
        must_reset_password=payload.must_reset_password,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

@router.post("/change-password")
def change_password(
    payload: schemas.PasswordChangeRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    validate_password_policy(payload.new_password)
    current_user.password_hash = hash_password(payload.new_password)
    current_user.must_reset_password = False
    db.commit()
    return {"status": "ok"}

def ensure_admin_user(db: Session):
    """
    Гарантируем, что админ-пользователь из .env существует
    и помечен как админ.
    ВАЖНО: initial password применяется только один раз при bootstrap,
    чтобы не перетирать рабочий пароль после каждого рестарта сервера.
    """
    admin = db.query(models.User).filter(models.User.name == ADMIN_NAME).first()
    if not admin:
        if not ADMIN_INITIAL_PASSWORD:
            # Без initial password не можем безопасно создать первого админа.
            return
        admin = models.User(name=ADMIN_NAME)
        db.add(admin)
        db.flush()
        admin.password_hash = hash_password(ADMIN_INITIAL_PASSWORD)
        admin.is_active = True
        admin.is_admin = True
        admin.must_reset_password = True
        db.commit()
        return

    # Для существующего пользователя обновляем только роль/статус,
    # но не трогаем пароль и флаг must_reset_password.
    changed = False
    if not admin.is_admin:
        admin.is_admin = True
        changed = True
    if not admin.is_active:
        admin.is_active = True
        changed = True
    if changed:
        db.commit()