from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import relationship
from .database import Base
from datetime import datetime

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Связь с транзакциями (как создатель)
    created_transactions = relationship("Transaction", back_populates="creator", foreign_keys="Transaction.created_by_user_id")

class Category(Base):
    __tablename__ = "categories"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    type = Column(String, nullable=False) # 'income', 'expense'
    parent_id = Column(Integer, ForeignKey("categories.id"), nullable=True)
    
    parent = relationship("Category", remote_side=[id], backref="children")
    transactions = relationship("Transaction", back_populates="category")

class Transaction(Base):
    __tablename__ = "transactions"
    
    id = Column(Integer, primary_key=True, index=True)
    amount = Column(Float, nullable=False)
    transaction_type = Column(String, nullable=False) # 'income', 'expense'
    category_id = Column(Integer, ForeignKey("categories.id"), nullable=False)
    description = Column(Text, nullable=True)
    date = Column(DateTime, nullable=False)
    created_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    
    category = relationship("Category", back_populates="transactions")
    creator = relationship("User", back_populates="created_transactions", foreign_keys=[created_by_user_id])

class CalendarEvent(Base):
    __tablename__ = "calendar_events"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    event_date = Column(DateTime, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    
    creator = relationship("User", backref="calendar_events")
