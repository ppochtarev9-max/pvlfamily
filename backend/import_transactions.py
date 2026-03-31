import csv
from datetime import datetime
from sqlalchemy.orm import Session
from app.database import engine, SessionLocal, Base
from app.models import User, Category, Transaction, TransactionType

# Пересоздаём таблицы (очищаем базу)
Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)

db: Session = SessionLocal()

try:
    # 1. Создаём пользователя "Я" (владелец данных)
    owner = db.query(User).filter(User.name == "Я").first()
    if not owner:
        owner = User(name="Я")
        db.add(owner)
        db.commit()
        db.refresh(owner)
    
    print(f"Пользователь: {owner.name} (ID: {owner.id})")

    # 2. Читаем CSV
    csv_file = "transactions_import.csv"
    categories_cache = {}  # Кэш: (type, parent_name, child_name) -> category_id

    with open(csv_file, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter=';')
        
        for row_num, row in enumerate(reader, start=2):
            date_str = row['Дата'].strip()
            view = row['Вид'].strip()
            category_name = row['Категория'].strip()
            subcategory_name = row['Подкатегория'].strip()
            amount_str = row['Сумма'].strip().replace('₽', '').replace(' ', '').replace(',', '.')
            
            # Парсим дату
            try:
                tx_date = datetime.strptime(date_str, "%d.%m.%Y")
            except ValueError:
                print(f"Ошибка даты в строке {row_num}: {date_str}")
                continue
            
            # Парсим сумму
            try:
                amount = float(amount_str)
            except ValueError:
                print(f"Ошибка суммы в строке {row_num}: {amount_str}")
                continue
            
            # Определяем тип операции
            if view == "Расход":
                tx_type = "expense"
            elif view == "Доход":
                tx_type = "income"
            elif view == "Перевод":
                tx_type = "transfer"
            else:
                print(f"Неизвестный вид операции в строке {row_num}: {view}")
                continue
            
            # Находим или создаём категорию (родитель)
            cat_key = (tx_type, category_name, None)
            parent_cat = db.query(Category).filter(
                Category.name == category_name,
                Category.type == tx_type,
                Category.parent_id.is_(None)
            ).first()
            
            if not parent_cat:
                parent_cat = Category(name=category_name, type=tx_type, parent_id=None)
                db.add(parent_cat)
                db.commit()
                db.refresh(parent_cat)
                print(f"Создана категория: {category_name} ({tx_type})")
            
            # Находим или создаём подкатегорию
            child_cat = db.query(Category).filter(
                Category.name == subcategory_name,
                Category.type == tx_type,
                Category.parent_id == parent_cat.id
            ).first()
            
            if not child_cat:
                child_cat = Category(name=subcategory_name, type=tx_type, parent_id=parent_cat.id)
                db.add(child_cat)
                db.commit()
                db.refresh(child_cat)
                print(f"  -> Создана подкатегория: {subcategory_name}")
            
            # Создаём транзакцию
            transaction = Transaction(
                amount=amount,
                transaction_type=tx_type,
                category_id=child_cat.id,
                description=f"Импорт из CSV ({view})",
                date=tx_date,
                created_by_user_id=owner.id
            )
            db.add(transaction)
            
            # Коммитим каждые 100 записей для производительности
            if row_num % 100 == 0:
                db.commit()
                print(f"Обработано {row_num} записей...")
    
    db.commit()
    print(f"\nГотово! Всего загружено транзакций: {db.query(Transaction).count()}")
    print(f"Всего категорий: {db.query(Category).count()}")

except Exception as e:
    db.rollback()
    print(f"Ошибка: {e}")
    raise
finally:
    db.close()
