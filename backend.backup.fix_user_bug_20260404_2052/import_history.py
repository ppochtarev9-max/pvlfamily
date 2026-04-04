import csv, re, os
from datetime import datetime

USER_NAME = "Паша"
CSV_FILE = "history.csv"

def parse_amount(s):
    if not s: return 0.0
    return float(re.sub(r'[^\d,.+-]', '', str(s)).replace(',', '.'))

def detect_encoding(path):
    with open(path, 'rb') as f:
        chunk = f.read(2048)
        if chunk.startswith(b'\xef\xbb\xbf'): return 'utf-8-sig'
        try:
            chunk.decode('utf-8')
            return 'utf-8'
        except: return 'windows-1251'

def main():
    print(f"=== ЗАГРУЗКА ИСТОРИИ ({USER_NAME}) ===")
    from app.database import SessionLocal
    from app.models import User, Category, Transaction
    
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.name == USER_NAME).first()
        if not user:
            print(f"❌ Пользователь '{USER_NAME}' не найден!")
            return
        
        print("🧹 Полная очистка данных...")
        db.query(Transaction).filter(Transaction.created_by_user_id == user.id).delete()
        db.query(Category).filter().delete()
        db.commit()
        
        if not os.path.exists(CSV_FILE):
            print(f"❌ Файл {CSV_FILE} не найден")
            return

        enc = detect_encoding(CSV_FILE)
        print(f"📂 Чтение файла (кодировка: {enc})...")
        
        cat_cache = {}
        cnt_cat = 0
        cnt_tx = 0

        with open(CSV_FILE, 'r', encoding=enc) as f:
            reader = csv.DictReader(f, delimiter=';')
            for i, row in enumerate(reader, 2):
                d_str = row.get('Дата', '').strip()
                v_str = row.get('Вид', '').strip()
                c_name = row.get('Категория', '').strip()
                s_name = row.get('Подкатегория', '').strip()
                a_str = row.get('Сумма', '0')

                if not d_str: continue
                try: dt = datetime.strptime(d_str, "%d.%m.%Y")
                except: continue

                amt = parse_amount(a_str)
                is_income = 'Доход' in v_str
                if is_income: amt = abs(amt)
                else: amt = -abs(amt)
                
                tx_type = "income" if is_income else "expense"

                # 1. Создаем/ищем Родителя
                cat_id = None
                if c_name:
                    key = (c_name, None)
                    if key not in cat_cache:
                        existing = db.query(Category).filter(Category.name==c_name, Category.parent_id.is_(None)).first()
                        if not existing:
                            existing = Category(name=c_name, type=tx_type, parent_id=None)
                            db.add(existing)
                            db.flush()
                            cnt_cat += 1
                            print(f"   + Категория: {c_name}")
                        cat_cache[key] = existing.id
                    cat_id = cat_cache[key]

                # 2. Создаем/ищем Подкатегорию (ВСЕ, включая "Я")
                final_id = cat_id
                if s_name and cat_id:
                    # Игнорируем только пустые или пробелы
                    clean_sub = s_name.strip()
                    if clean_sub:
                        key_s = (clean_sub, cat_id)
                        if key_s not in cat_cache:
                            existing_s = db.query(Category).filter(Category.name==clean_sub, Category.parent_id==cat_id).first()
                            if not existing_s:
                                parent = db.get(Category, cat_id)
                                p_type = parent.type if parent else tx_type
                                existing_s = Category(name=clean_sub, type=p_type, parent_id=cat_id)
                                db.add(existing_s)
                                db.flush()
                                cnt_cat += 1
                                print(f"      + Подкатегория: {clean_sub}")
                            cat_cache[key_s] = existing_s.id
                        final_id = cat_cache[key_s]

                if final_id:
                    tx = Transaction(
                        amount=amt, date=dt, category_id=final_id,
                        transaction_type=tx_type, created_by_user_id=user.id
                    )
                    db.add(tx)
                    cnt_tx += 1

        db.commit()
        print(f"\n✅ ГОТОВО! Категорий: {cnt_cat}, Транзакций: {cnt_tx}")

    except Exception as e:
        db.rollback()
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()
