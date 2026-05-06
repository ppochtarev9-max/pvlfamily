"""Сериализация дат в API как UTC ISO 8601 с суффиксом Z.

В SQLite DateTime хранится без таймзоны; по соглашению значения — «наивные» компоненты UTC
(как после парсинга ISO с Z и записи через SQLAlchemy). Клиентам всегда отдаём явный Z.
"""
from datetime import datetime, timezone
from typing import Optional


def format_db_datetime_as_utc_z(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        u = dt.replace(tzinfo=timezone.utc)
    else:
        u = dt.astimezone(timezone.utc)
    return u.strftime("%Y-%m-%dT%H:%M:%SZ")
