import csv, re, os
from datetime import datetime

USER_NAME = "Паша"
CSV_FILE = "history.csv"

def parse_amount(s):
    if not s: return 0.0
    # Удаляем все кроме цифр, запятых, точек и знаков
    clean_s = re.sub(r'[^\d,.+-]', '', str(s))
    # Заменяем запятую на точку для float
    return float(clean_s.replace(',', '.'))

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
    
    # ИМПОРТ ВНУТРИ ФУНКЦИИ
    from app.database import SessionLocal, engine, Base
    from app import models
    
    # Создаем таблицы по актуальным моделям
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.name == USER_NAME).first()
        if not user:
            print(f"❌ Пользователь '{USER_NAME}' не найден! Создайте его через приложение сначала.")
            return
        
        print("🧹 Полная очистка данных перед импортом...")
        # Порядок важен из-за внешних ключей (CASCADE обычно справляется, но лучше явно)
        db.query(models.Transaction).filter(models.Transaction.created_by_user_id == user.id).delete()
        db.query(models.Category).delete()
        db.query(models.CategoryGroup).delete()
        db.commit()
        print("✅ База очищена.")
        
        if not os.path.exists(CSV_FILE):
            print(f"❌ Файл {CSV_FILE} не найден в папке backend/")
            return

        enc = detect_encoding(CSV_FILE)
        print(f"📂 Чтение файла (кодировка: {enc})...")
        
        # Кэш структур: 
        # { "ГруппаName": { "id": 1, "type": "expense", "subs": { "SubName": 10 } } }
        group_cache = {} 
        
        cnt_groups = 0
        cnt_subs = 0
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

                # --- 1. РАБОТА С ГРУППой (бывшая "Категория") ---
                group_id = None
                if c_name:
                    if c_name not in group_cache:
                        # Ищем в БД
                        existing_group = db.query(models.CategoryGroup).filter(
                            models.CategoryGroup.name == c_name
                        ).first()
                        
                        if not existing_group:
                            # Создаем новую группу
                            # Важно: тип группы определяем по первой транзакции. 
                            # В идеале все транзакции группы должны быть одного типа.
                            existing_group = models.CategoryGroup(
                                name=c_name,
                                type=tx_type, 
                                is_hidden=False
                            )
                            db.add(existing_group)
                            db.flush() # Чтобы получить ID
                            cnt_groups += 1
                            print(f"   + Группа: {c_name} ({tx_type})")
                        
                        group_cache[c_name] = {
                            "id": existing_group.id,
                            "type": existing_group.type,
                            "subs": {}
                        }
                    
                    group_id = group_cache[c_name]["id"]

                # --- 2. РАБОТА С ПОДКАТЕГОРИЕЙ (бывшая "Подкатегория") ---
                final_category_id = None
                
                if s_name and group_id:
                    clean_sub = s_name.strip()
                    if clean_sub:
                        # Проверяем кэш внутри группы
                        cache_ref = group_cache[c_name]
                        if clean_sub not in cache_ref["subs"]:
                            # Ищем в БД
                            existing_sub = db.query(models.Category).filter(
                                models.Category.name == clean_sub,
                                models.Category.group_id == group_id
                            ).first()
                            
                            if not existing_sub:
                                # Создаем подкатегорию
                                # Поле type у Category больше нет! Только group_id
                                existing_sub = models.Category(
                                    name=clean_sub,
                                    group_id=group_id,
                                    is_hidden=False
                                )
                                db.add(existing_sub)
                                db.flush()
                                cnt_subs += 1
                                print(f"      + Подкатегория: {clean_sub}")
                            
                            cache_ref["subs"][clean_sub] = existing_sub.id
                        
                        final_category_id = cache_ref["subs"][clean_sub]
                elif group_id and not s_name:
                    # Если подкатегории нет в CSV, но есть группа.
                    # Создаем техническую подкатегию "Общее" внутри этой группы, 
                    # чтобы транзакция не висела в воздухе (так как FK обязателен).
                    # Или используем глобальную заглушку, если она есть.
                    # Для простоты импорта создадим "Общее" внутри группы, если нет в кэше.
                    
                    cache_ref = group_cache[c_name]
                    sub_name_default = "Общее"
                    
                    if sub_name_default not in cache_ref["subs"]:
                         existing_sub = db.query(models.Category).filter(
                            models.Category.name == sub_name_default,
                            models.Category.group_id == group_id
                        ).first()
                         
                         if not existing_sub:
                             existing_sub = models.Category(
                                 name=sub_name_default,
                                 group_id=group_id,
                                 is_hidden=False
                             )
                             db.add(existing_sub)
                             db.flush()
                             cnt_subs += 1
                             print(f"      + Подкатегория (авто): {sub_name_default}")
                         
                         cache_ref["subs"][sub_name_default] = existing_sub.id
                    
                    final_category_id = cache_ref["subs"][sub_name_default]

                # --- 3. СОЗДАНИЕ ТРАНЗАКЦИИ ---
                if final_category_id:
                    tx = models.Transaction(
                        amount=amt, 
                        date=dt, 
                        category_id=final_category_id, # Ссылка на SubCategory
                        transaction_type=tx_type, 
                        created_by_user_id=user.id,
                        creator_name_snapshot=user.name
                    )
                    db.add(tx)
                    cnt_tx += 1
                else:
                    print(f"⚠️ Пропущена строка {i}: нет категории")

        db.commit()
        print(f"\n✅ ГОТОВО!")
        print(f"   Создано групп: {cnt_groups}")
        print(f"   Создано подкатегорий: {cnt_subs}")
        print(f"   Импортировано транзакций: {cnt_tx}")

    except Exception as e:
        db.rollback()
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()