from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import relationship
from .database import Base
from datetime import datetime, timezone

# Исправление: используем timezone-aware datetime
def get_utc_now():
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, default=get_utc_now)
    
    # Связи обновлены: passive_deletes=True для корректной работы ondelete
    created_transactions = relationship("Transaction", back_populates="creator", foreign_keys="Transaction.created_by_user_id", passive_deletes=True)
    calendar_events = relationship("CalendarEvent", back_populates="creator", passive_deletes=True)

class Category(Base):
    __tablename__ = "categories"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    type = Column(String, nullable=False)
    parent_id = Column(Integer, ForeignKey("categories.id"), nullable=True)
    is_hidden = Column(Boolean, default=False)
    parent = relationship("Category", remote_side=[id], backref="children")
    transactions = relationship("Transaction", back_populates="category")

class Transaction(Base):
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True, index=True)
    amount = Column(Float, nullable=False)
    transaction_type = Column(String, nullable=False)
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=False)
    description = Column(Text, nullable=True)
    date = Column(DateTime, nullable=False)
    
    # ID пользователя (станет NULL при удалении)
    created_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    
    # НОВОЕ ПОЛЕ: Сохраняем имя пользователя на момент создания записи
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
    
    # ID пользователя (станет NULL при удалении)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    
    # НОВОЕ ПОЛЕ: Сохраняем имя пользователя на момент создания события
    creator_name_snapshot = Column(String, nullable=True)
    
    creator = relationship("User", back_populates="calendar_events", passive_deletes=True)

class BabyLog(Base):
    __tablename__ = "baby_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    
    # ID пользователя (станет NULL при удалении)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    
    # НОВОЕ ПОЛЕ: Сохраняем имя пользователя на момент создания записи
    creator_name_snapshot = Column(String, nullable=True)
    
    event_type = Column(String, nullable=False)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=True)
    duration_minutes = Column(Integer, default=0)
    note = Column(Text, nullable=True)
    created_at = Column(DateTime, default=get_utc_now)
    
    creator = relationship("User", backref="baby_logs", passive_deletes=True)