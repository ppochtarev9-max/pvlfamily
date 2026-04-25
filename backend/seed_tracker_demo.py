#!/usr/bin/env python3
"""
Сброс демо-данных трекера (baby_logs) и генерация фантазийных, но
монотонно упорядоченных по времени записей за N дней.

Использование (из каталога backend, с активированным venv):
  python seed_tracker_demo.py
  python seed_tracker_demo.py --user "Имя" --count 55 --days 7 --seed 42

По умолчанию удаляются ВСЕ строки в baby_logs. Пользователи, бюджет, календарь не трогаются.
"""
from __future__ import annotations

import argparse
import random
from datetime import datetime, timedelta, timezone

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Очистка baby_logs и демо-записи трекера")
    p.add_argument("--user", default=None, help="Имя пользователя (создатель). По умолчанию — первый user в БД")
    p.add_argument("--count", type=int, default=55, help="Сколько записей создать (50–60 разумно)")
    p.add_argument("--days", type=int, default=7, help="Интервал: последние N суток до «сейчас» (UTC)")
    p.add_argument("--seed", type=int, default=42, help="Seed RNG для воспроизводимости")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Только печать плана, без DELETE/INSERT",
    )
    return p.parse_args()


def get_user(db: Session, name: str | None):
    from app import models

    if name:
        u = db.query(models.User).filter(models.User.name == name).first()
        if not u:
            raise SystemExit(f"Пользователь «{name}» не найден")
        return u
    u = db.query(models.User).order_by(models.User.id.asc()).first()
    if not u:
        raise SystemExit("В БД нет пользователей — сначала создайте учётку")
    return u


def wipe_baby_logs(db: Session) -> int:
    from app import models

    n = db.query(models.BabyLog).count()
    if n:
        db.query(models.BabyLog).delete(synchronize_session=False)
        db.commit()
    return n


def build_timeline(anchor_end: datetime, days: int, count: int, rng: random.Random) -> list[dict]:
    """
    События в хронологическом порядке, без overlap.
    types: sleep (start < end), feed (мгновенное, start == end)
    """
    t0 = anchor_end - timedelta(days=days)
    events: list[dict] = []
    t = t0
    now = anchor_end
    max_steps = count * 8
    steps = 0
    while len(events) < count and t < now - timedelta(minutes=1) and steps < max_steps:
        steps += 1
        roll = rng.random()
        if roll < 0.42:
            duration = rng.randint(20, 200)
            t_end = t + timedelta(minutes=duration)
            if t_end > now - timedelta(minutes=2):
                t_end = now - timedelta(minutes=2)
            if t_end <= t + timedelta(minutes=5):
                t += timedelta(minutes=rng.randint(5, 20))
                continue
            events.append(
                {
                    "event_type": "sleep",
                    "start_time": t,
                    "end_time": t_end,
                    "note": "Демо: сон",
                }
            )
            t = t_end + timedelta(minutes=rng.randint(3, 60))
        elif roll < 0.75:
            events.append(
                {
                    "event_type": "feed",
                    "start_time": t,
                    "end_time": t,
                    "note": "Демо: кормление",
                }
            )
            t += timedelta(minutes=rng.randint(3, 90))
        else:
            duration = rng.randint(8, 30)
            t_end = t + timedelta(minutes=duration)
            if t_end > now - timedelta(minutes=2):
                t += timedelta(minutes=3)
                continue
            events.append(
                {
                    "event_type": "sleep",
                    "start_time": t,
                    "end_time": t_end,
                    "note": "Демо: дремота",
                }
            )
            t = t_end + timedelta(minutes=rng.randint(2, 40))

    if len(events) < count and t < now - timedelta(hours=1):
        # Добьём снами, если мало
        while len(events) < count and t < now - timedelta(minutes=5):
            duration = rng.randint(15, 90)
            t_end = t + timedelta(minutes=duration)
            if t_end > now - timedelta(minutes=2):
                t_end = now - timedelta(minutes=2)
            if t_end <= t + timedelta(minutes=3):
                break
            events.append(
                {
                    "event_type": "sleep",
                    "start_time": t,
                    "end_time": t_end,
                    "note": "Демо: сон (догонка)",
                }
            )
            t = t_end + timedelta(minutes=rng.randint(2, 30))

    return events[:count]


def insert_logs(db: Session, user, events: list[dict]) -> int:
    from app import models

    created = 0
    for e in events:
        if e["event_type"] == "sleep":
            st, en = e["start_time"], e["end_time"]
            delta = en - st
            dur = max(0, int(delta.total_seconds() // 60))
        else:
            st = en = e["start_time"]
            dur = 0
        log = models.BabyLog(
            user_id=user.id,
            event_type=e["event_type"],
            start_time=st,
            end_time=en,
            duration_minutes=dur,
            note=e.get("note"),
            creator_name_snapshot=user.name,
        )
        db.add(log)
        created += 1
    db.commit()
    return created


def main() -> None:
    args = parse_args()
    rng = random.Random(args.seed)

    from app.database import Base, engine, SessionLocal
    from app import models

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        user = get_user(db, args.user)
        now = datetime.now(timezone.utc)
        deleted = db.query(models.BabyLog).count() if not args.dry_run else 0
        if args.dry_run:
            print(f"DRY-RUN: сейчас в baby_logs строк: {db.query(models.BabyLog).count()}")
        else:
            deleted = wipe_baby_logs(db)
            print(f"Удалено записей baby_logs: {deleted}")

        events = build_timeline(now, args.days, args.count, rng)
        events.sort(key=lambda x: (x["start_time"], (x.get("end_time") or x["start_time"])))
        if not events:
            print("Событий не сгенерировано (слишком мало окна / много веток). Увеличьте --days.")
            return
        # Обрезка/доп. сон в конец: если последняя — не sleep, закрываем сценарий
        if events[-1]["event_type"] != "sleep":
            last_t = max(x["end_time"] or x["start_time"] for x in events) + timedelta(minutes=15)
            if last_t < now - timedelta(minutes=30):
                end = last_t + timedelta(minutes=rng.randint(40, 120))
                if end < now - timedelta(minutes=5):
                    events.append(
                        {
                            "event_type": "sleep",
                            "start_time": last_t,
                            "end_time": end,
                            "note": "Демо: ночной сон (завершён)",
                        }
                    )
        if args.dry_run:
            print(f"DRY-RUN: было бы вставлено {len(events)} событий (user id={user.id}, {user.name})")
            for ev in events[:5]:
                print("  ...", ev)
            print(f"  ... всего {len(events)}")
            return

        n = insert_logs(db, user, events)
        print(f"Создано baby_logs: {n} (пользователь: {user.name}, id={user.id})")
        first = min(e["start_time"] for e in events)
        last = max(
            (e.get("end_time") or e["start_time"] for e in events),
        )
        print(f"Окно: {first.isoformat()} … {last.isoformat()} (UTC)")
    finally:
        db.close()


if __name__ == "__main__":
    main()
