import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database import SessionLocal, engine
from app import models

# Убеждаемся, что таблицы созданы по новым моделям
models.Base.metadata.create_all(bind=engine)

db = SessionLocal()

try:
    # 1. Группа-заглушка
    DEFAULT_GROUP_NAME = "Без категории"
    DEFAULT_GROUP_TYPE = "expense"
    
    group = db.query(models.CategoryGroup).filter(
        models.CategoryGroup.name == DEFAULT_GROUP_NAME
    ).first()
    
    if not group:
        print(f"📦 Создание группы-заглушки '{DEFAULT_GROUP_NAME}'...")
        group = models.CategoryGroup(
            name=DEFAULT_GROUP_NAME,
            type=DEFAULT_GROUP_TYPE,
            is_hidden=True
        )
        db.add(group)
        db.commit()
        db.refresh(group)
        print(f"✅ Группа создана (ID: {group.id})")
    else:
        print(f"ℹ️ Группа-заглушка уже существует (ID: {group.id})")

    # 2. Подкатегория-заглушка
    DEFAULT_SUB_NAME = "Общее"
    
    subcategory = db.query(models.Category).filter(
        models.Category.name == DEFAULT_SUB_NAME,
        models.Category.group_id == group.id
    ).first()
    
    if not subcategory:
        print(f"📦 Создание подкатегории-заглушки '{DEFAULT_SUB_NAME}'...")
        # ВНИМАНИЕ: Здесь НЕТ поля type! Только name, group_id, is_hidden
        subcategory = models.Category(
            name=DEFAULT_SUB_NAME,
            group_id=group.id,
            is_hidden=True
        )
        db.add(subcategory)
        db.commit()
        db.refresh(subcategory)
        print(f"✅ Подкатегория создана (ID: {subcategory.id})")
    else:
        print(f"ℹ️ Подкатегория-заглушка уже существует (ID: {subcategory.id})")

    print("\n🎉 ГОТОВО!")
    print(f"   ID подкатегории-заглушки: {subcategory.id}")
    print(f"   Вставь это число в iOS код вместо DEFAULT_SUBCATEGORY_ID.")

except Exception as e:
    db.rollback()
    print(f"❌ Ошибка: {e}")
finally:
    db.close()