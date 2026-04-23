from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import relationship
from .database import Base
from datetime import datetime, timezone

def get_utc_now():
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, default=get_utc_now)
    
    created_transactions = relationship("Transaction", back_populates="creator", foreign_keys="Transaction.created_by_user_id", passive_deletes=True)
    calendar_events = relationship("CalendarEvent", back_populates="creator", passive_deletes=True)

# НОВАЯ МОДЕЛЬ: ГРУППА КАТЕГОРИЙ (бывшие "родители")
class CategoryGroup(Base):
    __tablename__ = "category_groups"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False, index=True) # Например: "Коммуникации", "Еда"
    type = Column(String, nullable=False) # "income" или "expense" (наследуется подкатегориями)
    is_hidden = Column(Boolean, default=False)
    
    # Связь с подкатегориями
    subcategories = relationship("Category", back_populates="group", cascade="all, delete-orphan")

# ОБНОВЛЕННАЯ МОДЕЛЬ: ПОДКАТЕГОРИЯ (бывшие "дети")
class Category(Base):
    __tablename__ = "categories"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False) # Например: "Подписки", "Продукты"
    
    # Внешний ключ на группу (обязательный)
    group_id = Column(Integer, ForeignKey("category_groups.id", ondelete="CASCADE"), nullable=False)
    
    is_hidden = Column(Boolean, default=False)
    
    # Связи
    group = relationship("CategoryGroup", back_populates="subcategories")
    transactions = relationship("Transaction", back_populates="category")

class Transaction(Base):
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True, index=True)
    amount = Column(Float, nullable=False)
    transaction_type = Column(String, nullable=False)
    
    # Ссылка на подкатегорию
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=False)
    
    description = Column(Text, nullable=True)
    date = Column(DateTime, nullable=False)
    
    created_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    creator_name_snapshot = Column(String, nullable=True)
    
    category = relationship("Category", back_populates="transactions")
    creator = relationship("User", back_populates="created_transactions", foreign_keys=[created_by_user_id], passive_deletes=True)

class CalendarEvent(Base):
    __tablename__ = "calendar_events"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    event_date = Column(DateTime, nullable=False)
    event_type = Column(String, default="event")
    
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    creator_name_snapshot = Column(String, nullable=True)
    
    creator = relationship("User", back_populates="calendar_events", passive_deletes=True)

class BabyLog(Base):
    __tablename__ = "baby_logs"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    creator_name_snapshot = Column(String, nullable=True)
    event_type = Column(String, nullable=False)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=True)
    duration_minutes = Column(Integer, default=0)
    note = Column(Text, nullable=True)
    created_at = Column(DateTime, default=get_utc_now)
    creator = relationship("User", backref="baby_logs", passive_deletes=True)