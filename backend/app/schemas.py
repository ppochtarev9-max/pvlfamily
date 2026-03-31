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
class CategoryCreate(BaseModel):
    name: str
    type: str

class CategoryResponse(BaseModel):
    id: int
    name: str
    type: str
    
    class Config:
        from_attributes = True

# --- Transaction Schemas ---
# Убрали вложенность CategoryResponse, чтобы избежать ошибок порядка объявления
class TransactionCreate(BaseModel):
    amount: float
    category_id: int
    description: Optional[str] = None

class TransactionResponse(BaseModel):
    id: int
    amount: float
    description: Optional[str]
    date: datetime
    category_id: int
    category_name: str  # Передаем имя категории плоским полем
    category_type: str  # И тип категории
    
    class Config:
        from_attributes = True

# --- Event Schemas ---
class EventCreate(BaseModel):
    title: str
    event_type: str = "general"
    event_date: datetime
    description: Optional[str] = None

class EventResponse(BaseModel):
    id: int
    title: str
    event_type: str
    event_date: datetime
    description: Optional[str]
    
    class Config:
        from_attributes = True
