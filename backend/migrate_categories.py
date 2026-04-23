import sqlite3
import os
from datetime import datetime

# Путь к базе данных
DB_PATH = "pvlfamily.db"

def migrate():
    if not os.path.exists(DB_PATH):
        print(f"❌ База данных не найдена: {DB_PATH}")
        return

    print(f"🔄 Начало миграции категорий в {DB_PATH}...")
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    try:
        # 1. Проверка: существует ли уже новая таблица category_groups?
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='category_groups'")
        if cursor.fetchone():
            print("⚠️ Таблица 'category_groups' уже существует. Миграция, возможно, уже проведена.")
            # Можно добавить проверку на наличие данных, если нужно
            # return 

        # 2. Читаем ВСЕ старые категории
        # Нам нужно понять, какие из них были родителями (у них parent_id IS NULL), 
        # а какие детьми (parent_id IS NOT NULL).
        cursor.execute("""
            SELECT id, name, type, parent_id, is_hidden 
            FROM categories 
            ORDER BY id
        """)
        old_categories = cursor.fetchall()
        
        if not old_categories:
            print("ℹ️ Старые категории не найдены. Нечего мигрировать.")
            return

        print(f"📂 Найдено старых записей: {len(old_categories)}")

        # 3. Создаем новые таблицы вручную (так как модели могут не совпадать или Alembic не настроен)
        # Таблица Групп (бывшие родители)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS category_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL, -- 'income' или 'expense' для группировки
                is_hidden BOOLEAN DEFAULT 0
            )
        """)
        
        # Таблица Подкатегорий (бывшие дети, теперь все здесь, но со ссылкой на группу)
        # Мы сохраняем старую таблицу categories, но меняем её структуру или создаем новую?
        # В новом models.py у нас две таблицы. Значит, старую categories надо переименовать или дропнуть.
        # Но проще: создать новую таблицу подкатегорий, а старую переименовать в backup.
        
        # Переименуем старую таблицу в backup, чтобы не потерять данные万一
        cursor.execute("ALTER TABLE categories RENAME TO categories_backup_old")
        
        # Создаем новую таблицу categories (теперь это подкатегории)
        cursor.execute("""
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                group_id INTEGER,
                is_hidden BOOLEAN DEFAULT 0,
                FOREIGN KEY (group_id) REFERENCES category_groups (id) ON DELETE SET NULL
            )
        """)
        
        # 4. Логика переноса
        # Словарь для маппинга: old_parent_id -> new_group_id
        # Если у записи parent_id IS NULL, значит это была Группа.
        # Если parent_id IS NOT NULL, значит это Подкатегория, и parent_id ссылается на ID группы.
        
        id_mapping = {} # old_id -> new_id
        
        # Сначала создаем Группы (те, у кого parent_id был NULL)
        groups_to_insert = []
        subcats_to_insert = []
        
        for old_id, name, type_val, parent_id, is_hidden in old_categories:
            if parent_id is None:
                # Это была Группа
                groups_to_insert.append((name, type_val, is_hidden))
            else:
                # Это была Подкатегория (пока не знаем ID новой группы, соберем в кучу)
                subcats_to_insert.append((old_id, name, type_val, parent_id, is_hidden))
        
        # Вставляем Группы
        print(f"➕ Создание групп: {len(groups_to_insert)}")
        for name, type_val, is_hidden in groups_to_insert:
            cursor.execute("INSERT INTO category_groups (name, type, is_hidden) VALUES (?, ?, ?)", 
                           (name, type_val, is_hidden))
            # Запоминаем последний вставленный ID
            # Но нам нужно сопоставить old_id (который был NULL? Нет, у группы есть свой ID) 
            # Стоп. В старой модели у ГРУППЫ тоже был ID. И у ПОДКАТЕГОРИИ parent_id ссылался на этот ID.
            # Значит, нам нужно сохранить mapping: old_group_id -> new_group_id.
            
        # Получаем все созданные группы, чтобы построить маппинг
        # Проблема: мы не знаем, какой new_id соответствует какому old_id, так как вставляли пачкой.
        # Давайте перечитаем группы по имени? Имена могут дублироваться? Надеемся, что нет в рамках типа.
        # Лучше вставлять по одной и мапить сразу.
        
        # Очистим и сделаем правильно по одной записи
        cursor.execute("DELETE FROM category_groups") # На случай если выше что-то вставилось
        
        old_groups = [c for c in old_categories if c[3] is None] # parent_id is None
        
        for old_id, name, type_val, _, is_hidden in old_groups:
            cursor.execute("INSERT INTO category_groups (name, type, is_hidden) VALUES (?, ?, ?)", 
                           (name, type_val, is_hidden))
            new_id = cursor.lastrowid
            id_mapping[old_id] = new_id
            print(f"   🗺 Маппинг: Старая группа ID={old_id} ('{name}') -> Новая группа ID={new_id}")

        # Теперь вставляем Подкатегории
        print(f"➕ Создание подкатегорий: {len(subcats_to_insert)}")
        for old_id, name, type_val, old_parent_id, is_hidden in subcats_to_insert:
            new_group_id = id_mapping.get(old_parent_id)
            if new_group_id is None:
                print(f"   ⚠️ Предупреждение: Для подкатегории '{name}' (old_id={old_id}) не найдена родительская группа (old_parent_id={old_parent_id}). Пропускаем связь.")
                # Можно решить вставить без группы или пропустить. Вставим без группы (NULL).
            
            cursor.execute("""
                INSERT INTO categories (name, type, group_id, is_hidden) 
                VALUES (?, ?, ?, ?)
            """, (name, type_val, new_group_id, is_hidden))
            
        # 5. Обновление связей в транзакциях?
        # В таблице transactions поле category_id ссылается на OLD ID категории (подкатегории).
        # Новые подкатегории получили NEW ID (autoincrement).
        # НАМ НУЖНО обновить category_id в таблице transactions!
        
        # Построим обратный маппинг для подкатегорий: old_subcat_id -> new_subcat_id
        # Для этого выберем все старые подкатегории и новые подкатегории.
        # Это сложно сделать без явного сохранения ID при вставке.
        
        # Давайте сделаем хитрее: выберем новые подкатегории по имени и типу (и группе).
        # Но имена могут повторяться.
        
        # Правильный подход: при вставке подкатегорий сохранять маппинг.
        # Перезапустим логику вставки подкатегорий с маппингом.
        
        # Сначала удалим только что вставленные подкатегории, чтобы вставить снова с маппингом
        cursor.execute("DELETE FROM categories")
        
        subcat_id_mapping = {} # old_subcat_id -> new_subcat_id
        
        for old_id, name, type_val, old_parent_id, is_hidden in subcats_to_insert:
            new_group_id = id_mapping.get(old_parent_id)
            
            cursor.execute("""
                INSERT INTO categories (name, type, group_id, is_hidden) 
                VALUES (?, ?, ?, ?)
            """, (name, type_val, new_group_id, is_hidden))
            
            new_subcat_id = cursor.lastrowid
            subcat_id_mapping[old_id] = new_subcat_id
            print(f"   🗺 Маппинг: Старая подкатегория ID={old_id} ('{name}') -> Новая ID={new_subcat_id}")

        # 6. ОБНОВЛЕНИЕ ТАБЛИЦЫ TRANSACTIONS
        print("🔄 Обновление связей в транзакциях...")
        updated_count = 0
        for old_id, new_id in subcat_id_mapping.items():
            # Обновляем все транзакции, где category_id = old_id
            cursor.execute("UPDATE transactions SET category_id = ? WHERE category_id = ?", (new_id, old_id))
            updated_count += cursor.rowcount
            
        print(f"   ✅ Обновлено транзакций: {updated_count}")

        conn.commit()
        print("✅ Миграция успешно завершена!")
        print("💡 Не забудьте перезапустить сервер и проверить работу категорий.")

    except Exception as e:
        conn.rollback()
        print(f"❌ Ошибка миграции: {e}")
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()