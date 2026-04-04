from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime
from typing import Optional, List

from .database import get_db
from .models import Transaction, Category, User
from .auth import get_current_user

router = APIRouter()

def parse_date(date_str: Optional[str]) -> datetime:
    if not date_str:
        return datetime.now()
    
    # Пробуем разные форматы
    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d"
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    raise HTTPException(status_code=400, detail="Неверный формат даты. Используйте YYYY-MM-DD")

@router.get("/summary")
def get_dashboard_summary(
    as_of_date: Optional[str] = None,
    user_id: Optional[int] = Query(None, description="ID пользователя (None или 0 = все пользователи)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Определяем дату отсечки
    try:
        cutoff_date = parse_date(as_of_date)
    except HTTPException:
        raise
    
    # Начинаем базовый запрос
    query = db.query(Transaction).filter(Transaction.date <= cutoff_date)
    
    # Логика фильтрации по пользователю:
    # 1. Если user_id передан и он > 0, фильтруем строго по этому ID.
    # 2. Если user_id не передан (None) или равен 0, показываем данные ВСЕХ пользователей.
    if user_id is not None and user_id > 0:
        query = query.filter(Transaction.created_by_user_id == user_id)
        target_label = str(user_id)
    else:
        # Фильтр не применяем, берутся все транзакции
        target_label = "all"
    
    transactions = query.all()
    
    # Считаем суммы
    # Расходы в базе отрицательные, доходы положительные.
    total_income = sum(t.amount for t in transactions if t.transaction_type == "income")
    total_expense = sum(t.amount for t in transactions if t.transaction_type == "expense")
    
    # Общий баланс - это просто сумма всех транзакций (доходы + расходы)
    balance = total_income + total_expense
    
    return {
        "as_of_date": cutoff_date.strftime("%Y-%m-%d %H:%M"),
        "user_filter": target_label,
        "total_income": round(total_income, 2),
        "total_expense": round(total_expense, 2), # Оставляем отрицательным, как в базе
        "balance": round(balance, 2)
    }

@router.get("/monthly-stats")
def get_monthly_stats(
    year: Optional[int] = None,
    month: Optional[int] = None,
    user_id: Optional[int] = Query(None, description="ID пользователя (None или 0 = все пользователи)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    now = datetime.now()
    y = year if year is not None else now.year
    m = month if month is not None else now.month
    
    start_date = datetime(y, m, 1)
    if m == 12:
        end_date = datetime(y + 1, 1, 1)
    else:
        end_date = datetime(y, m + 1, 1)
        
    # Базовый запрос с фильтрами по дате
    query = db.query(
        Transaction.transaction_type,
        Transaction.category_id,
        func.sum(Transaction.amount).label("total")
    ).filter(
        Transaction.date >= start_date,
        Transaction.date < end_date
    )
    
    # Применяем фильтр по пользователю аналогично summary
    if user_id is not None and user_id > 0:
        query = query.filter(Transaction.created_by_user_id == user_id)
    
    query = query.group_by(
        Transaction.transaction_type,
        Transaction.category_id
    )
    
    rows = query.all()
    
    details = []
    for r in rows:
        cat_name = "Без категории"
        if r.category_id:
            cat = db.query(Category).filter(Category.id == r.category_id).first()
            if cat:
                cat_name = cat.name
        
        details.append({
            "category_id": r.category_id,
            "category_name": cat_name,
            "type": r.transaction_type,
            "amount": round(r.total, 2)
        })
    
    # Считаем итоги
    t_inc = sum(x["amount"] for x in details if x["type"] == "income")
    t_exp = sum(x["amount"] for x in details if x["type"] == "expense")
    
    return {
        "year": y,
        "month": m,
        "total_income": round(t_inc, 2),
        "total_expense": round(t_exp, 2),
        "balance": round(t_inc + t_exp, 2),
        "details": details
    }