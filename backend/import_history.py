import argparse
import csv
import os
import re
from datetime import datetime


DEFAULT_USER_NAME = "Паша"
DEFAULT_CSV_FILE = "history.csv"


def parse_amount(raw_value: str) -> float:
    if not raw_value:
        return 0.0
    normalized = re.sub(r"[^\d,.+-]", "", str(raw_value)).replace(",", ".")
    return float(normalized) if normalized else 0.0


def detect_encoding(path: str) -> str:
    with open(path, "rb") as f:
        chunk = f.read(2048)
        if chunk.startswith(b"\xef\xbb\xbf"):
            return "utf-8-sig"
        try:
            chunk.decode("utf-8")
            return "utf-8"
        except UnicodeDecodeError:
            return "windows-1251"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Импорт истории транзакций из CSV в новую модель groups/subcategories.")
    parser.add_argument("--user", default=DEFAULT_USER_NAME, help="Имя пользователя, от имени которого создаются транзакции.")
    parser.add_argument("--csv", default=DEFAULT_CSV_FILE, help="Путь к CSV-файлу истории.")
    parser.add_argument("--dry-run", action="store_true", help="Проверка без записи в БД.")
    parser.add_argument(
        "--replace-user-transactions",
        action="store_true",
        help="Удалить существующие транзакции пользователя перед импортом.",
    )
    parser.add_argument(
        "--wipe-all-transactions",
        action="store_true",
        help="ОПАСНО: удалить ВСЕ транзакции ВСЕХ пользователей перед импортом (требует --yes, если не dry-run).",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Подтверждение опасных операций (нужно для --wipe-all-transactions в режиме записи).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    print(f"=== ИМПОРТ ИСТОРИИ ({args.user}) ===")
    print(f"CSV: {args.csv}")
    print(f"Режим: {'DRY-RUN' if args.dry_run else 'WRITE'}")

    from app.database import SessionLocal, engine, Base
    from app import models

    Base.metadata.create_all(bind=engine)

    if not os.path.exists(args.csv):
        print(f"❌ Файл не найден: {args.csv}")
        return

    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.name == args.user).first()
        if not user:
            print(f"❌ Пользователь '{args.user}' не найден")
            return

        if args.wipe_all_transactions and args.replace_user_transactions:
            print("❌ Нельзя одновременно использовать --wipe-all-transactions и --replace-user-transactions")
            return

        if args.wipe_all_transactions and (not args.dry_run) and (not args.yes):
            print("❌ Для удаления ВСЕХ транзакций нужен флаг подтверждения --yes")
            print("   Пример: python import_history.py --wipe-all-transactions --yes")
            return

        if args.wipe_all_transactions:
            total_tx = db.query(models.Transaction).count()
            print(f"🧨 Удаление ВСЕХ транзакций в БД: {total_tx}")
            if not args.dry_run:
                db.query(models.Transaction).delete(synchronize_session=False)
                db.commit()

        if args.replace_user_transactions:
            n = db.query(models.Transaction).filter(models.Transaction.created_by_user_id == user.id).count()
            print(f"🧹 Удаление существующих транзакций пользователя: {n}")
            db.query(models.Transaction).filter(models.Transaction.created_by_user_id == user.id).delete(synchronize_session=False)
            if not args.dry_run:
                db.commit()

        enc = detect_encoding(args.csv)
        print(f"📂 Чтение CSV (кодировка: {enc})...")

        group_cache = {}
        subcategory_cache = {}

        created_groups = 0
        created_subcategories = 0
        imported_transactions = 0
        skipped_rows = 0

        with open(args.csv, "r", encoding=enc) as f:
            # В некоторых экспортерах перед заголовком могут быть пустые строки вида ';;;;;;'.
            # Найдём реальную строку заголовка (где есть «Дата» и «Категория») и начнём читать после неё.
            raw_reader = csv.reader(f, delimiter=";")
            header: list[str] | None = None
            header_row_num = 0
            for row_num, row in enumerate(raw_reader, start=1):
                if not row or all((c or "").strip() == "" for c in row):
                    continue
                if any((c or "").strip() == "Дата" for c in row) and any((c or "").strip() == "Категория" for c in row):
                    header = [(c or "").strip() for c in row]
                    header_row_num = row_num
                    break

            if not header:
                print("❌ Не найден заголовок CSV (ожидались колонки «Дата» и «Категория»).")
                return

            # Часто CSV идёт с ведущим ';' → первая колонка без имени. Уберём её.
            if header and header[0] == "":
                header = header[1:]

            for row_num, row in enumerate(raw_reader, start=header_row_num + 1):
                if not row or all((c or "").strip() == "" for c in row):
                    continue
                if header and len(row) > 0 and (row[0] or "").strip() == "" and len(row) == len(header) + 1:
                    # Аналогично: ведущий пустой столбец в данных.
                    row = row[1:]
                if len(row) < len(header):
                    skipped_rows += 1
                    continue

                row_dict = {header[i]: (row[i] if i < len(row) else "") for i in range(len(header))}
                date_str = (row_dict.get("Дата") or "").strip()
                kind_str = (row_dict.get("Вид") or "").strip()
                group_name = (row_dict.get("Категория") or "").strip()
                sub_name = (row_dict.get("Подкатегория") or "").strip()
                amount_str = row_dict.get("Сумма", "0")
                comment = (row_dict.get("Комментарий") or "").strip()

                if not date_str or not group_name:
                    skipped_rows += 1
                    continue

                try:
                    tx_date = datetime.strptime(date_str, "%d.%m.%Y")
                except ValueError:
                    print(f"⚠️ Строка {row_num}: некорректная дата '{date_str}', пропуск")
                    skipped_rows += 1
                    continue

                is_income = "Доход" in kind_str
                tx_type = "income" if is_income else "expense"
                amount = parse_amount(amount_str)
                amount = abs(amount) if is_income else -abs(amount)

                group_key = (group_name, tx_type)
                group = group_cache.get(group_key)
                if not group:
                    group = (
                        db.query(models.CategoryGroup)
                        .filter(
                            models.CategoryGroup.name == group_name,
                            models.CategoryGroup.type == tx_type,
                        )
                        .first()
                    )
                    if not group:
                        group = models.CategoryGroup(name=group_name, type=tx_type, is_hidden=False)
                        db.add(group)
                        db.flush()
                        created_groups += 1
                        print(f"   + Группа: {group_name} ({tx_type})")
                    group_cache[group_key] = group

                if not sub_name:
                    sub_name = "Общее"

                sub_key = (sub_name, group.id)
                sub = subcategory_cache.get(sub_key)
                if not sub:
                    sub = (
                        db.query(models.Category)
                        .filter(
                            models.Category.name == sub_name,
                            models.Category.group_id == group.id,
                        )
                        .first()
                    )
                    if not sub:
                        sub = models.Category(name=sub_name, group_id=group.id, is_hidden=False)
                        db.add(sub)
                        db.flush()
                        created_subcategories += 1
                        print(f"      + Подкатегория: {sub_name}")
                    subcategory_cache[sub_key] = sub

                tx = models.Transaction(
                    amount=amount,
                    transaction_type=tx_type,
                    category_id=sub.id,
                    description=comment or None,
                    date=tx_date,
                    created_by_user_id=user.id,
                    creator_name_snapshot=user.name,
                )
                db.add(tx)
                imported_transactions += 1

        if args.dry_run:
            db.rollback()
            print("🧪 DRY-RUN завершен: изменения не сохранены.")
        else:
            db.commit()
            print("✅ Импорт завершен: изменения сохранены.")

        print(
            "Итог: "
            f"групп создано={created_groups}, "
            f"подкатегорий создано={created_subcategories}, "
            f"транзакций импортировано={imported_transactions}, "
            f"строк пропущено={skipped_rows}"
        )

    except Exception as exc:
        db.rollback()
        print(f"❌ Ошибка импорта: {exc}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()


if __name__ == "__main__":
    main()