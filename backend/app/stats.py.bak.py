from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime
from typing import Optional

from .database import get_db
from .models import Transaction, Category, User
from .auth import get_current_user

router = APIRouter()

@router.get("/summary")
def get_dashboard_summary(
    year: Optional[int] = None,
    month: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    now = datetime.now()
    y = year if year is not None else now.year
    m = month if month is not None else now.month
    
    # Границы месяца
    start_date = datetime(y, m, 1)
    if m == 12:
        end_date = datetime(y + 1, 1, 1)
    else:
        end_date = datetime(y, m + 1, 1)

    # Доходы за месяц
    income = db.query(func.sum(Transaction.amount)).filter(
        Transaction.created_by_user_id == current_user.id,
        Transaction.transaction_type == "income",
        Transaction.date >= start_date,
        Transaction.date < end_date
    ).scalar() or 0.0

    # Расходы за месяц
    expense = db.query(func.sum(Transaction.amount)).filter(
        Transaction.created_by_user_id == current_user.id,
        Transaction.transaction_type == "expense",
        Transaction.date >= start_date,
        Transaction.date < end_date
    ).scalar() or 0.0
    
    # Общий баланс (все время)
    total_income_all = db.query(func.sum(Transaction.amount)).filter(
        Transaction.created_by_user_id == current_user.id,
        Transaction.transaction_type == "income"
    ).scalar() or 0.0
    
    total_expense_all = db.query(func.sum(Transaction.amount)).filter(
        Transaction.created_by_user_id == current_user.id,
        Transaction.transaction_type == "expense"
    ).scalar() or 0.0
    
    total_balance = total_income_all - total_expense_all

    return {
        "balance": round(total_balance, 2),          # Ожидаемое поле
        "total_income": round(income, 2),            # Ожидаемое поле (доходы за месяц)
        "total_expense": round(expense, 2),          # Ожидаемое поле (расходы за месяц)
        "period": f"{y}-{m:02d}",
        "month_income": round(income, 2),
        "month_expense": round(expense, 2),
        "month_balance": round(income - expense, 2),
        "total_balance": round(total_balance, 2)
    }

@router.get("/monthly-stats")
def get_monthly_stats(
    year: Optional[int] = None,
    month: Optional[int] = None,
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
    
    rows = db.query(
        Transaction.transaction_type,
        Transaction.category_id,
        func.sum(Transaction.amount).label("total")
    ).filter(
        Transaction.created_by_user_id == current_user.id,
        Transaction.date >= start_date,
        Transaction.date < end_date
    ).group_by(
        Transaction.transaction_type,
        Transaction.category_id
    ).all()
    
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
    
    t_inc = sum(x["amount"] for x in details if x["type"] == "income")
    t_exp = sum(x["amount"] for x in details if x["type"] == "expense")
    
    return {
        "year": y,
        "month": m,
        "total_income": round(t_inc, 2),
        "total_expense": round(t_exp, 2),
        "balance": round(t_inc - t_exp, 2),
        "details": details
    }
