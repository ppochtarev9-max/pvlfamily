from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class UserBase(BaseModel): name: str
class UserCreate(UserBase): pass
class UserOut(UserBase):
    id: int; created_at: datetime
    class Config: from_attributes = True

class CategoryBase(BaseModel): name: str; type: str
class CategoryCreate(CategoryBase): parent_id: Optional[int] = None
class CategoryOut(CategoryBase):
    id: int; parent_id: Optional[int] = None
    class Config: from_attributes = True

class TransactionBase(BaseModel):
    amount: float; transaction_type: str; category_id: int
    description: Optional[str] = None; date: datetime
class TransactionCreate(TransactionBase): pass
class TransactionUpdate(BaseModel):
    amount: Optional[float] = None; category_id: Optional[int] = None
    description: Optional[str] = None; date: Optional[datetime] = None
    transaction_type: Optional[str] = None
class TransactionOut(TransactionBase):
    id: int; created_by_user_id: Optional[int] = None
    category_name: Optional[str] = None; full_category_path: str = ""
    creator_name: Optional[str] = None
    class Config: from_attributes = True

class EventBase(BaseModel):
    title: str; description: Optional[str] = None
    event_date: datetime; event_type: str = "event"
class EventCreate(EventBase): pass
class EventResponse(EventBase):
    id: int; user_id: Optional[int] = None
    class Config: from_attributes = True
