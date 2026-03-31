import csv
import re
from datetime import datetime
from app.database import SessionLocal, engine, Base
from app.models import User, Category, Transaction, TransactionType

# НАСТРОЙКИ
USER_NAME = "Паша"  # Имя пользователя в базе
CSV_FILE = "history.csv"

def parse_amount(amount_str):
    """Очистка строки суммы от мусора (₽, пробелы) и преобразование в float."""
    if not amount_str:
        return 0.0
    # Удаляем все кроме цифр, точки, запятой и минуса
    clean_str = re.sub(r'[^\d,.-]', '', str(amount_str))
    # Заменяем запятую на точку
    clean_str = clean_str.replace(',', '.')
    try:
        return float(clean_str)
    except ValueError:
        return 0.0

def get_or_create_category(db, name, type_str, parent_id=None):
    """Находит категорию или создает новую."""
    category = db.query(Category).filter(
        Category.name == name,
        Category.type == type_str,
        Category.parent_id == parent_id
    ).first()
    
    if not category:
        category = Category(name=name, type=type_str, parent_id=parent_id)
        db.add(category)
        db.flush()  # Получаем ID сразу
        print(f"   [+] Создана категория: {name} ({type_str})")
    return category

def main():
    print(f"=== ЗАГРУЗКА ИСТОРИЧЕСКИХ ДАННЫХ ===")
    print(f"Пользователь: {USER_NAME}")
    print(f"Файл: {CSV_FILE}")
    
    # Создаем таблицы, если их нет
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    
    try:
        # 1. Находим пользователя
        user = db.query(User).filter(User.name == USER_NAME).first()
        if not user:
            # Если не нашли по имени "Паша", пробуем "Pavel"
            user = db.query(User).filter(User.name == "Pavel").first()
        
        if not user:
            print(f"❌ Ошибка: Пользователь '{USER_NAME}' не найден в базе.")
            print("Создадим тестового пользователя для демонстрации...")
            user = User(name=USER_NAME)
            db.add(user)
            db.commit()
            db.refresh(user)
            print(f"✅ Пользователь создан: {user.name} (ID: {user.id})")
        else:
            print(f"✅ Пользователь найден: {user.name} (ID: {user.id})")

        # 2. ОЧИСТКА данных пользователя
        print(f"\n⚠️ Очистка старых данных для пользователя {user.name}...")
        
        # Удаляем транзакции
        deleted_trans = db.query(Transaction).filter(Transaction.created_by_user_id == user.id).delete(synchronize_session=False)
        
        # Удаляем категории (сначала дочерние, потом родительские - SQLAlchemy справится с FK)
        # Но лучше удалять все категории пользователя
        # В данной схеме у категорий нет явного owner_id, они общие? 
        # Проверим схему: в models.py у Category нет owner_id. 
        # Значит категории общие для всех. Нам нужно удалить только те, которые мы создадим, 
        # ИЛИ очистить всю таблицу категорий и транзакций полностью перед импортом.
        # По ТЗ: "все текущие данные в бд надо будет очистить предварительно".
        # Очищаем ВСЕ транзакции и ВСЕ категории.
        
        deleted_cats = db.query(Category).delete(synchronize_session=False)
        
        db.commit()
        print(f"   Удалено транзакций: {deleted_trans}")
        print(f"   Удалено категорий: {deleted_cats}")

        # 3. Чтение CSV и импорт
        print(f"\n📥 Чтение файла {CSV_FILE}...")
        
        created_cats_count = 0
        created_trans_count = 0
        category_cache = {} # Кэш: (name, type, parent_id) -> id

        with open(CSV_FILE, mode='r', encoding='utf-8') as file:
            reader = csv.DictReader(file, delimiter=';')
            
            for row in reader:
                date_str = row.get('Дата', '').strip()
                view_str = row.get('Вид', '').strip() # Расход / Доход
                cat_name = row.get('Категория', '').strip()
                subcat_name = row.get('Подкатегория', '').strip()
                amount_raw = row.get('Сумма', '0')

                # Парсинг даты
                try:
                    dt = datetime.strptime(date_str, "%d.%m.%Y")
                except ValueError:
                    print(f"⚠️ Пропущена строка с неверной датой: {date_str}")
                    continue

                # Парсинг суммы и знака
                amount = parse_amount(amount_raw)
                if view_str == 'Расход':
                    amount = -abs(amount)
                    type_str = "expense"
                elif view_str == 'Доход':
                    amount = abs(amount)
                    type_str = "income"
                else:
                    type_str = "expense" # По умолчанию

                # Обработка категорий
                parent_id = None
                
                # Создаем/находим родительскую категорию
                if cat_name:
                    cache_key_parent = (cat_name, type_str, None)
                    if cache_key_parent not in category_cache:
                        parent_cat = get_or_create_category(db, cat_name, type_str, parent_id=None)
                        category_cache[cache_key_parent] = parent_cat.id
                        created_cats_count += 1
                    parent_id = category_cache[cache_key_parent]

                final_cat_id = parent_id

                # Создаем/находим подкатегорию, если есть
                # Исключаем случаи типа "Я" в подкатегории дохода, если это не реальная подкатегория
                if subcat_name and subcat_name.lower() != 'я' and subcat_name:
                    if parent_id:
                        cache_key_sub = (subcat_name, type_str, parent_id)
                        if cache_key_sub not in category_cache:
                            sub_cat = get_or_create_category(db, subcat_name, type_str, parent_id=parent_id)
                            category_cache[cache_key_sub] = sub_cat.id
                            created_cats_count += 1
                        final_cat_id = category_cache[cache_key_sub]

                # Создаем транзакцию
                new_trans = Transaction(
                    amount=amount,
                    transaction_type=type_str,
                    category_id=final_cat_id,
                    description=f"Импорт: {view_str}",
                    date=dt,
                    created_by_user_id=user.id
                )
                db.add(new_trans)
                created_trans_count += 1

        db.commit()
        
        print("\n=== ИМПОРТ ЗАВЕРШЕН ===")
        print(f"✅ Создано категорий: {created_cats_count}")
        print(f"✅ Создано транзакций: {created_trans_count}")

    except Exception as e:
        db.rollback()
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()
