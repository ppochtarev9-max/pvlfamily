from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime

# --- User Schemas ---
class UserBase(BaseModel):
    name: str

class UserCreate(UserBase):
    pass

class UserOut(UserBase):
    id: int
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

# --- Category Schemas ---
class CategoryBase(BaseModel):
    name: str
    type: str

class CategoryCreate(CategoryBase):
    parent_id: Optional[int] = None

class CategoryOut(CategoryBase):
    is_hidden: bool = False
    id: int
    parent_id: Optional[int] = None
    model_config = ConfigDict(from_attributes=True)

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
    category_name: Optional[str] = None
    full_category_path: str = ""
    # Это поле будет содержать либо реальное имя, либо "Имя (удален)"
    creator_name: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

# --- Calendar Event Schemas ---
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
    # Добавлено поле для имени создателя
    creator_name: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

# --- Baby Tracker Schemas ---
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
    # Добавлено поле для имени создателя
    creator_name: Optional[str] = None
    # Новое поле: активно ли событие (нет end_time)
    is_active: bool = False    
    model_config = ConfigDict(from_attributes=True)