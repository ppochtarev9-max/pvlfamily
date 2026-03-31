from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

# --- User ---
class UserBase(BaseModel):
    name: str

class UserCreate(UserBase):
    pass

class UserOut(UserBase):
    id: int
    created_at: datetime
    
    class Config:
        from_attributes = True

# --- Category ---
class CategoryBase(BaseModel):
    name: str
    type: str

class CategoryCreate(CategoryBase):
    parent_id: Optional[int] = None

class CategoryOut(CategoryBase):
    id: int
    parent_id: Optional[int] = None
    
    class Config:
        from_attributes = True

# --- Transaction ---
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
    # Дополнительные поля для отображения (заполняются вручную в роуте)
    category_name: Optional[str] = None
    full_category_path: str = ""
    creator_name: Optional[str] = None
    
    class Config:
        from_attributes = True

# --- Calendar Events (необходимо для calendar.py) ---
class EventBase(BaseModel):
    title: str
    start_date: datetime
    end_date: Optional[datetime] = None
    description: Optional[str] = None

class EventCreate(EventBase):
    pass

class EventUpdate(BaseModel):
    title: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    description: Optional[str] = None

class EventResponse(EventBase):
    id: int
    created_by_user_id: Optional[int] = None
    
    class Config:
        from_attributes = True

# --- Calendar ---
class EventBase(BaseModel):
    title: str
    description: Optional[str] = None
    event_date: datetime

class EventCreate(EventBase):
    pass

class EventResponse(EventBase):
    id: int
    user_id: Optional[int] = None
    
    class Config:
        from_attributes = True

class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    parent_id: Optional[int] = None
