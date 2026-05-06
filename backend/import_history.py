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
    parser.add_argument("--user-id", type=int, default=None, help="ID пользователя (если нужно выбрать не по имени).")
    parser.add_argument("--csv", default=DEFAULT_CSV_FILE, help="Путь к CSV-файлу истории.")
    parser.add_argument("--dry-run", action="store_true", help="Проверка без записи в БД.")
    parser.add_argument(
        "--wipe-transactions",
        action="store_true",
        help="Удалить существующие транзакции выбранного пользователя перед импортом.",
    )
    parser.add_argument(
        "--wipe-all-budget",
        action="store_true",
        help="Удалить транзакции пользователя и очистить сиротские категории/группы (чтобы не оставался мусор).",
    )
    # Backward compatibility (старые флаги)
    parser.add_argument(
        "--replace-user-transactions",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--wipe-all-transactions",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Подтверждение опасных операций wipe (нужно в режиме записи).",
    )
    return parser.parse_args()


def _get_user(db, models, user_name: str, user_id: int | None):
    if user_id is not None:
        return db.query(models.User).filter(models.User.id == user_id).first()
    return db.query(models.User).filter(models.User.name == user_name).first()


def _wipe_user_transactions(db, models, user_id: int, dry_run: bool) -> int:
    q = db.query(models.Transaction).filter(models.Transaction.created_by_user_id == user_id)
    n = q.count()
    print(f"🧹 Удаление транзакций пользователя: {n}")
    if n and (not dry_run):
        q.delete(synchronize_session=False)
        db.commit()
    return n


def _cleanup_orphan_budget_entities(db, models, dry_run: bool) -> tuple[int, int]:
    """
    Удаляет:
    - Category без транзакций
    - CategoryGroup без подкатегорий

    Это безопасно при многопользовательской БД: удаляются только «сироты».
    """
    orphan_categories_q = db.query(models.Category).filter(
        ~db.query(models.Transaction.id).filter(models.Transaction.category_id == models.Category.id).exists()
    )
    orphan_categories = orphan_categories_q.count()

    orphan_groups_q = db.query(models.CategoryGroup).filter(
        ~db.query(models.Category.id).filter(models.Category.group_id == models.CategoryGroup.id).exists()
    )
    orphan_groups = orphan_groups_q.count()

    print(f"🧹 Сиротских подкатегорий (Category) к удалению: {orphan_categories}")
    print(f"🧹 Сиротских групп (CategoryGroup) к удалению: {orphan_groups}")

    if not dry_run:
        if orphan_categories:
            orphan_categories_q.delete(synchronize_session=False)
        if orphan_groups:
            orphan_groups_q.delete(synchronize_session=False)
        db.commit()

    return orphan_categories, orphan_groups


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
        # Legacy-флаги → новые (чтобы старые инструкции/алиасы не ломались).
        if getattr(args, "replace_user_transactions", False):
            args.wipe_transactions = True
        if getattr(args, "wipe_all_transactions", False):
            args.wipe_all_budget = True

        user = _get_user(db, models, user_name=args.user, user_id=args.user_id)
        if not user:
            who = f"id={args.user_id}" if args.user_id is not None else f"'{args.user}'"
            print(f"❌ Пользователь {who} не найден")
            return

        if args.wipe_all_budget and args.wipe_transactions:
            print("❌ Нельзя одновременно использовать --wipe-all-budget и --wipe-transactions (wipe-all-budget уже включает wipe-transactions)")
            return

        if (args.wipe_all_budget or args.wipe_transactions) and (not args.dry_run) and (not args.yes):
            print("❌ Для операций wipe в режиме записи нужен флаг подтверждения --yes")
            print("   Пример: python import_history.py --wipe-all-budget --yes")
            return

        if args.wipe_all_budget:
            _wipe_user_transactions(db, models, user.id, dry_run=args.dry_run)
            _cleanup_orphan_budget_entities(db, models, dry_run=args.dry_run)
        elif args.wipe_transactions:
            _wipe_user_transactions(db, models, user.id, dry_run=args.dry_run)

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