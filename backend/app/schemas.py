from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

# --- User Schemas ---
class UserCreate(BaseModel):
    name: str

class UserOut(BaseModel):
    id: int
    name: str
    class Config:
        from_attributes = True

# --- Category Schemas ---
class CategoryBase(BaseModel):
    name: str
    type: str # income, expense, transfer
    parent_id: Optional[int] = None

class CategoryCreate(CategoryBase):
    pass

class CategoryResponse(CategoryBase):
    id: int
    children: List["CategoryResponse"] = []
    
    class Config:
        from_attributes = True

class CategoryUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    # parent_id менять опасно, если уже есть дети, но пока разрешим
    parent_id: Optional[int] = None

# Обновляем forward reference для рекурсивной структуры детей
CategoryResponse.update_forward_refs()

# --- Transaction Schemas ---
class TransactionBase(BaseModel):
    amount: float
    transaction_type: str # income, expense, transfer
    category_id: int
    description: Optional[str] = None
    date: Optional[datetime] = None

class TransactionCreate(TransactionBase):
    pass

class TransactionUpdate(BaseModel):
    amount: Optional[float] = None
    transaction_type: Optional[str] = None
    category_id: Optional[int] = None
    description: Optional[str] = None
    date: Optional[datetime] = None

class TransactionResponse(TransactionBase):
    id: int
    date: datetime
    created_by_user_id: Optional[int] = None
    creator_name: Optional[str] = None
    category_name: Optional[str] = None
    
    class Config:
        from_attributes = True

# --- Event Schemas (КАЛЕНДАРЬ) ---
class EventBase(BaseModel):
    title: str
    event_type: str = "general" # general, birthday, reminder
    event_date: datetime
    description: Optional[str] = None

class EventCreate(EventBase):
    pass

class EventUpdate(BaseModel):
    title: Optional[str] = None
    event_type: Optional[str] = None
    event_date: Optional[datetime] = None
    description: Optional[str] = None

class EventResponse(EventBase):
    id: int
    created_by_user_id: Optional[int] = None
    creator_name: Optional[str] = None
    
    class Config:
        from_attributes = True
