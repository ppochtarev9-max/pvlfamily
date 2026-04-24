from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime

# --- User Schemas ---
class UserBase(BaseModel):
    name: str

class UserCreate(UserBase):
    pass

class UserLogin(BaseModel):
    name: str
    password: str

class AdminUserCreate(BaseModel):
    name: str
    password: str
    is_active: bool = True
    must_reset_password: bool = True

class PasswordChangeRequest(BaseModel):
    new_password: str

class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    name: str
    force_password_reset: bool = False

class UserOut(UserBase):
    id: int
    is_active: bool = True
    is_admin: bool = False
    must_reset_password: bool = False
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

# --- Category Group Schemas (КАТЕГОРИИ) ---
class CategoryGroupBase(BaseModel):
    name: str
    type: str # "income" или "expense"

class CategoryGroupCreate(CategoryGroupBase):
    pass

class CategoryGroupOut(CategoryGroupBase):
    id: int
    is_hidden: bool = False
    # Вложенный список подкатегорий для удобства
    subcategories: List["CategoryOut"] = []
    model_config = ConfigDict(from_attributes=True)

# --- Category Schemas (ПОДКАТЕГОРИИ) ---
class CategoryBase(BaseModel):
    name: str
    group_id: int

class CategoryCreate(CategoryBase):
    pass

class CategoryOut(CategoryBase):
    id: int
    is_hidden: bool = False
    group_name: Optional[str] = None # Имя родительской категории для отображения
    model_config = ConfigDict(from_attributes=True)

# Обновляем ForwardRef для циклической зависимости
CategoryGroupOut.model_rebuild()

# --- Transaction Schemas ---
class TransactionBase(BaseModel):
    amount: float
    transaction_type: str
    category_id: int
    description: Optional[str] = None
    date: datetime

class TransactionCreate(TransactionBase):
    pass

class TransactionUpdate(BaseModel):
    amount: Optional[float] = None
    category_id: Optional[int] = None
    description: Optional[str] = None
    date: Optional[datetime] = None
    transaction_type: Optional[str] = None

class TransactionOut(TransactionBase):
    id: int
    created_by_user_id: Optional[int] = None
    balance: Optional[float] = None
    # Путь: "Категория / Подкатегория"
    full_category_path: str = "" 
    creator_name: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

# --- Остальные схемы без изменений ---
class EventBase(BaseModel):
    title: str
    description: Optional[str] = None
    event_date: datetime
    event_type: str = "event"

class EventCreate(EventBase):
    pass

class EventResponse(EventBase):
    id: int
    user_id: Optional[int] = None
    creator_name: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class BabyLogBase(BaseModel):
    event_type: str
    start_time: datetime
    end_time: Optional[datetime] = None
    note: Optional[str] = None

class BabyLogCreate(BabyLogBase):
    pass

class BabyLogUpdate(BaseModel):
    end_time: Optional[datetime] = None
    note: Optional[str] = None
    duration_minutes: Optional[int] = None

class BabyLogOut(BabyLogBase):
    id: int
    user_id: Optional[int] = None
    duration_minutes: int = 0
    created_at: datetime
    creator_name: Optional[str] = None
    is_active: bool = False    
    model_config = ConfigDict(from_attributes=True)