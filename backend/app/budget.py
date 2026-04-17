from fastapi import APIRouter, Depends, HTTPException, status, Response, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
import io
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.table import Table, TableStyleInfo
from fastapi.responses import StreamingResponse

from . import models, schemas
from .auth import get_current_user
from .database import get_db

router = APIRouter()

# ==========================================
# КАТЕГОРИИ
# ==========================================

@router.get("/categories", response_model=List[schemas.CategoryOut])
def get_categories(db: Session = Depends(get_db)):
    return db.query(models.Category).all()

@router.post("/categories", response_model=schemas.CategoryOut, status_code=201)
def create_category(cat: schemas.CategoryCreate, db: Session = Depends(get_db)):
    if cat.parent_id:
        parent = db.get(models.Category, cat.parent_id)
        if parent:
            cat.type = parent.type
    
    db_cat = models.Category(name=cat.name, type=cat.type, parent_id=cat.parent_id)
    db.add(db_cat)
    db.commit()
    db.refresh(db_cat)
    return db_cat

@router.put("/categories/{cat_id}", response_model=schemas.CategoryOut)
def update_category(cat_id: int, cat_in: schemas.CategoryCreate, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    if cat_in.name:
        obj.name = cat_in.name
    if cat_in.type:
        obj.type = cat_in.type
    if cat_in.parent_id is not None:
        obj.parent_id = cat_in.parent_id
    db.commit()
    db.refresh(obj)
    return obj

@router.delete("/categories/{cat_id}")
def delete_category(cat_id: int, db: Session = Depends(get_db)):
    ids = [cat_id]
    def find_children(pid):
        for c in db.query(models.Category).filter(models.Category.parent_id == pid).all():
            ids.append(c.id)
            find_children(c.id)
    find_children(cat_id)
    
    db.query(models.Transaction).filter(models.Transaction.category_id.in_(ids)).delete(synchronize_session=False)
    db.query(models.Category).filter(models.Category.id.in_(ids)).delete(synchronize_session=False)
    db.commit()
    return {"status": "deleted"}

# ==========================================
# СКРЫТИЕ КАТЕГОРИЙ
# ==========================================

def get_all_descendants(db: Session, parent_id: int) -> List[int]:
    ids = []
    children = db.query(models.Category).filter(models.Category.parent_id == parent_id).all()
    for child in children:
        ids.append(child.id)
        ids.extend(get_all_descendants(db, child.id))
    return ids

@router.post("/categories/{cat_id}/hide")
def hide_category(cat_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj: raise HTTPException(404, "Not found")
    
    obj.is_hidden = True
    db.commit()
    
    descendant_ids = get_all_descendants(db, cat_id)
    if descendant_ids:
        db.query(models.Category).filter(models.Category.id.in_(descendant_ids)).update({"is_hidden": True}, synchronize_session=False)
        db.commit()
    return {"status": "hidden"}

@router.post("/categories/{cat_id}/unhide")
def unhide_category(cat_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Category).filter(models.Category.id == cat_id).first()
    if not obj: raise HTTPException(404, "Not found")
    
    if obj.parent_id:
        parent = db.get(models.Category, obj.parent_id)
        if parent and parent.is_hidden:
            raise HTTPException(400, detail="Сначала восстановите родителя")
    
    obj.is_hidden = False
    db.commit()
    
    descendant_ids = get_all_descendants(db, cat_id)
    if descendant_ids:
        db.query(models.Category).filter(models.Category.id.in_(descendant_ids)).update({"is_hidden": False}, synchronize_session=False)
        db.commit()
    return {"status": "visible"}

# ==========================================
# ТРАНЗАКЦИИ
# ==========================================

def make_tx_resp(t):
    if not t:
        return None
    
    path = t.category.name if t.category else "No Cat"
    if t.category and t.category.parent:
        path = f"{t.category.parent.name} / {t.category.name}"
    
    if isinstance(t.date, datetime):
        date_str = t.date.strftime("%Y-%m-%dT%H:%M:%S")
    else:
        date_str = str(t.date)
        
    creator_display_name = "Неизвестно"
    if t.creator_name_snapshot:
        creator_display_name = t.creator_name_snapshot
    elif t.creator:
        creator_display_name = t.creator.name
    else:
        creator_display_name = "Пользователь (удален)"
        
    return schemas.TransactionOut(
        id=t.id, 
        amount=t.amount, 
        transaction_type=t.transaction_type,
        category_id=t.category_id, 
        description=t.description,
        date=date_str,
        creator_name=creator_display_name,
        category_name=path
    )

@router.get("/transactions", response_model=List[schemas.TransactionOut])
def get_transactions(response: Response, db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    
    all_txs = db.query(models.Transaction).order_by(models.Transaction.date.asc()).all()
    
    current_balance = 0.0
    calculated_data = []
    
    for t in all_txs:
        current_balance += t.amount
        calculated_data.append({'tx': t, 'balance': current_balance})
    
    result = []
    for item in reversed(calculated_data):
        resp = make_tx_resp(item['tx'])
        resp.balance = item['balance']
        result.append(resp)
        
    return result

@router.post("/transactions", response_model=schemas.TransactionOut, status_code=201)
def create_transaction(
    tx: schemas.TransactionCreate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    db_tx = models.Transaction(
        amount=tx.amount, 
        transaction_type=tx.transaction_type,
        category_id=tx.category_id, 
        description=tx.description,
        date=tx.date, 
        created_by_user_id=current_user.id,
        creator_name_snapshot=current_user.name
    )
    db.add(db_tx)
    db.commit()
    db.refresh(db_tx)
    resp = make_tx_resp(db_tx)
    if resp is None:
        raise HTTPException(status_code=500, detail="Ошибка создания")
    return resp
    
@router.get("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def get_transaction(tx_id: int, db: Session = Depends(get_db)):
    t = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Not found")
    return make_tx_resp(t)

@router.put("/transactions/{tx_id}", response_model=schemas.TransactionOut)
def update_transaction(tx_id: int, tx: schemas.TransactionUpdate, db: Session = Depends(get_db)):
    obj = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    
    update_data = tx.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(obj, key, value)
    
    db.commit()
    db.refresh(obj)
    resp = make_tx_resp(obj)
    if resp is None:
        raise HTTPException(status_code=500, detail="Ошибка сериализации")
    return resp

@router.delete("/transactions/{tx_id}")
def delete_transaction(tx_id: int, db: Session = Depends(get_db)):
    obj = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Not found")
    
    db.delete(obj)
    db.commit()
    return {"status": "deleted"}

# ==========================================
# ЭКСПОРТ В EXCEL (ОБНОВЛЕННЫЙ)
# ==========================================

@router.get("/export/excel")
def export_budget_excel(
    start_date: str = Query(None),
    end_date: str = Query(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    query = db.query(models.Transaction).filter(models.Transaction.created_by_user_id == current_user.id)
    
    if start_date:
        try:
            sd = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            query = query.filter(models.Transaction.date >= sd)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid start_date format")
            
    if end_date:
        try:
            ed = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
            query = query.filter(models.Transaction.date <= ed)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid end_date format")
            
    transactions = query.order_by(models.Transaction.date.desc()).all()
    
    wb = Workbook()
    ws = wb.active
    ws.title = "Budget History"
    
    # Заголовки
    headers = ["ID", "Date", "Amount", "Type", "Category", "Subcategory", "Description", "Creator"]
    ws.append(headers)
    
    # Стили для заголовков
    header_fill = PatternFill(start_color="4F81BD", end_color="4F81BD", fill_type="solid")
    header_font = Font(bold=True, color="FFFFFF")
    header_alignment = Alignment(horizontal="center", vertical="center")
    thin_border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))
    
    # Применяем стили к заголовкам
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = header_alignment
        cell.border = thin_border
        
    # Данные
    for t in transactions:
        cat_name = t.category.name if t.category else ""
        subcat_name = t.category.parent.name if (t.category and t.category.parent) else ""
        
        date_val = t.date.strftime("%Y-%m-%d %H:%M") if isinstance(t.date, datetime) else str(t.date)
        
        row = [
            t.id,
            date_val,
            t.amount,
            t.transaction_type,
            cat_name,
            subcat_name,
            t.description or "",
            t.creator_name_snapshot or "Unknown"
        ]
        ws.append(row)
    
    # Авто-ширина колонок
    for col in ws.columns:
        max_length = 0
        column = col[0].column_letter
        for cell in col:
            try:
                if len(str(cell.value)) > max_length:
                    max_length = len(str(cell.value))
            except:
                pass
        adjusted_width = (max_length + 2)
        ws.column_dimensions[column].width = min(adjusted_width, 50) # Макс 50 символов
        
    # Заморозка шапки
    ws.freeze_panes = "A2"
    
    # Создание умной таблицы (с фильтрами)
    # Диапазон таблицы: от A1 до последней заполненной ячейки
    max_row = ws.max_row
    max_col = ws.max_column
    tab_ref = f"A1:{ws.cell(row=max_row, column=max_col).coordinate}"
    
    table = Table(displayName="BudgetTable", ref=tab_ref)
    style = TableStyleInfo(name="TableStyleMedium2", showFirstColumn=False, showLastColumn=False, showRowStripes=True, showColumnStripes=False)
    table.tableStyleInfo = style
    
    ws.add_table(table)
    
    # Сохранение в буфер
    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    
    filename = f"budget_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )