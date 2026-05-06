from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from . import models


@dataclass(frozen=True)
class BudgetPayloadOptions:
    anchor_month: date
    window_months: int = 72  # 6 лет
    user_id: Optional[int] = None  # None = все (семья)


def _month_start(d: date) -> date:
    return date(d.year, d.month, 1)


def _add_months(d: date, delta: int) -> date:
    # Простая безопасная математика по месяцу.
    y = d.year + (d.month - 1 + delta) // 12
    m = (d.month - 1 + delta) % 12 + 1
    return date(y, m, 1)


def _ym_label(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def _parse_anchor_month(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    raw = value.strip()
    # ожидаем yyyy-mm
    try:
        parts = raw.split("-")
        if len(parts) != 2:
            return None
        y = int(parts[0])
        m = int(parts[1])
        if not (1 <= m <= 12):
            return None
        return date(y, m, 1)
    except Exception:
        return None


def build_budget_safe_payload(
    db: Session,
    *,
    anchor_month: date,
    window_months: int = 72,
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Собирает агрегированный safe_payload для LLM по бюджету из БД.
    Никаких сырых описаний/строк транзакций не отдаём; только агрегаты.
    """
    window_months = max(6, min(int(window_months or 72), 120))  # 6..120
    anchor = _month_start(anchor_month)
    start = _add_months(anchor, -(window_months - 1))
    end_exclusive = _add_months(anchor, 1)

    q = db.query(models.Transaction).filter(
        models.Transaction.date >= datetime(start.year, start.month, 1),
        models.Transaction.date < datetime(end_exclusive.year, end_exclusive.month, 1),
    )
    if user_id is not None:
        q = q.filter(models.Transaction.created_by_user_id == user_id)

    # --- coverage ---
    first_dt = q.with_entities(func.min(models.Transaction.date)).scalar()
    last_dt = q.with_entities(func.max(models.Transaction.date)).scalar()
    coverage_months = 0
    if first_dt and last_dt:
        coverage_months = (last_dt.year - first_dt.year) * 12 + (last_dt.month - first_dt.month) + 1

    # --- monthly series: income/expense/balance ---
    month_key = func.strftime("%Y-%m", models.Transaction.date)
    series_rows = (
        q.with_entities(
            month_key.label("ym"),
            func.sum(
                func.case(
                    (models.Transaction.transaction_type == "income", models.Transaction.amount),
                    else_=0.0,
                )
            ).label("income"),
            func.sum(
                func.case(
                    (models.Transaction.transaction_type == "expense", func.abs(models.Transaction.amount)),
                    else_=0.0,
                )
            ).label("expense"),
            func.sum(models.Transaction.amount).label("balance"),
        )
        .group_by("ym")
        .order_by("ym")
        .all()
    )
    # выравниваем “пустые месяцы” нулями
    by_ym = {r.ym: (float(r.income or 0), float(r.expense or 0), float(r.balance or 0)) for r in series_rows}
    months: List[date] = [_add_months(start, i) for i in range(window_months)]
    points_income = [{"t": _ym_label(m), "v": by_ym.get(_ym_label(m), (0.0, 0.0, 0.0))[0]} for m in months]
    points_expense = [{"t": _ym_label(m), "v": by_ym.get(_ym_label(m), (0.0, 0.0, 0.0))[1]} for m in months]
    points_balance = [{"t": _ym_label(m), "v": by_ym.get(_ym_label(m), (0.0, 0.0, 0.0))[2]} for m in months]

    # --- comparisons: MoM, YoY, last12 vs prev12 ---
    def sum_range(a: date, b_excl: date) -> Tuple[float, float, float]:
        qq = db.query(models.Transaction).filter(
            models.Transaction.date >= datetime(a.year, a.month, 1),
            models.Transaction.date < datetime(b_excl.year, b_excl.month, 1),
        )
        if user_id is not None:
            qq = qq.filter(models.Transaction.created_by_user_id == user_id)
        inc = (
            qq.with_entities(func.sum(func.case((models.Transaction.transaction_type == "income", models.Transaction.amount), else_=0.0)))
            .scalar()
            or 0.0
        )
        exp = (
            qq.with_entities(func.sum(func.case((models.Transaction.transaction_type == "expense", func.abs(models.Transaction.amount)), else_=0.0)))
            .scalar()
            or 0.0
        )
        bal = (qq.with_entities(func.sum(models.Transaction.amount)).scalar() or 0.0)
        return float(inc), float(exp), float(bal)

    cur_inc, cur_exp, cur_bal = sum_range(anchor, end_exclusive)
    prev_m = _add_months(anchor, -1)
    prev_inc, prev_exp, prev_bal = sum_range(prev_m, anchor)
    yoy_m = _add_months(anchor, -12)
    yoy_inc, yoy_exp, yoy_bal = sum_range(yoy_m, _add_months(yoy_m, 1))

    last12_start = _add_months(anchor, -11)
    last12_inc, last12_exp, last12_bal = sum_range(last12_start, end_exclusive)
    prev12_start = _add_months(anchor, -23)
    prev12_end = _add_months(anchor, -11)
    prev12_inc, prev12_exp, prev12_bal = sum_range(prev12_start, prev12_end)

    def delta_pct(a: float, b: float) -> Optional[float]:
        return ((a - b) / b * 100.0) if b and b != 0 else None

    comparisons: List[Dict[str, Any]] = [
        {
            "name": "Расходы: текущий vs прошлый месяц",
            "a_label": _ym_label(anchor),
            "a_value": cur_exp,
            "b_label": _ym_label(prev_m),
            "b_value": prev_exp,
            "delta": cur_exp - prev_exp,
            "delta_pct": delta_pct(cur_exp, prev_exp),
            "unit": "RUB",
        },
        {
            "name": "Доходы: текущий vs прошлый месяц",
            "a_label": _ym_label(anchor),
            "a_value": cur_inc,
            "b_label": _ym_label(prev_m),
            "b_value": prev_inc,
            "delta": cur_inc - prev_inc,
            "delta_pct": delta_pct(cur_inc, prev_inc),
            "unit": "RUB",
        },
        {
            "name": "Расходы: YoY (тот же месяц год назад)",
            "a_label": _ym_label(anchor),
            "a_value": cur_exp,
            "b_label": _ym_label(yoy_m),
            "b_value": yoy_exp,
            "delta": cur_exp - yoy_exp,
            "delta_pct": delta_pct(cur_exp, yoy_exp),
            "unit": "RUB",
        },
        {
            "name": "Доходы: YoY (тот же месяц год назад)",
            "a_label": _ym_label(anchor),
            "a_value": cur_inc,
            "b_label": _ym_label(yoy_m),
            "b_value": yoy_inc,
            "delta": cur_inc - yoy_inc,
            "delta_pct": delta_pct(cur_inc, yoy_inc),
            "unit": "RUB",
        },
        {
            "name": "Расходы: последние 12м vs предыдущие 12м",
            "a_label": f"{_ym_label(last12_start)}..{_ym_label(anchor)}",
            "a_value": last12_exp,
            "b_label": f"{_ym_label(prev12_start)}..{_ym_label(prev12_end)}",
            "b_value": prev12_exp,
            "delta": last12_exp - prev12_exp,
            "delta_pct": delta_pct(last12_exp, prev12_exp),
            "unit": "RUB",
        },
    ]

    # --- breakdowns: top groups for current month + last12 ---
    qj = q.join(models.Category, models.Transaction.category_id == models.Category.id).join(
        models.CategoryGroup, models.Category.group_id == models.CategoryGroup.id
    )
    cur_month_q = qj.filter(
        models.Transaction.date >= datetime(anchor.year, anchor.month, 1),
        models.Transaction.date < datetime(end_exclusive.year, end_exclusive.month, 1),
        models.Transaction.transaction_type == "expense",
    )
    cur_groups = (
        cur_month_q.with_entities(models.CategoryGroup.name, func.sum(func.abs(models.Transaction.amount)).label("v"))
        .group_by(models.CategoryGroup.name)
        .order_by(func.sum(func.abs(models.Transaction.amount)).desc())
        .limit(10)
        .all()
    )
    cur_total = float(sum(float(x.v or 0) for x in cur_groups) or 0.0)
    cur_items = [
        {"name": str(name), "value": float(v or 0), "share": (float(v or 0) / cur_total) if cur_total > 0 else None}
        for name, v in cur_groups
    ]
    breakdowns: List[Dict[str, Any]] = []
    if cur_items:
        breakdowns.append({"name": "Расходы по группам (месяц)", "items": cur_items, "unit": "RUB"})

    # --- anomalies: top ops last 12 months (без описаний) ---
    a_start = last12_start
    anomalies_q = db.query(models.Transaction).filter(
        models.Transaction.date >= datetime(a_start.year, a_start.month, 1),
        models.Transaction.date < datetime(end_exclusive.year, end_exclusive.month, 1),
    )
    if user_id is not None:
        anomalies_q = anomalies_q.filter(models.Transaction.created_by_user_id == user_id)
    anomalies_q = anomalies_q.join(models.Category).join(models.CategoryGroup)
    top_ops = (
        anomalies_q.with_entities(
            func.strftime("%Y-%m-%d", models.Transaction.date).label("d"),
            models.Transaction.transaction_type.label("type"),
            func.abs(models.Transaction.amount).label("amount_abs"),
            models.CategoryGroup.name.label("group"),
            models.Category.name.label("subcategory"),
        )
        .order_by(func.abs(models.Transaction.amount).desc())
        .limit(12)
        .all()
    )
    anomalies = [
        {
            "date": str(r.d),
            "type": str(r.type),
            "amount": float(r.amount_abs or 0),
            "group": str(r.group),
            "subcategory": str(r.subcategory),
        }
        for r in top_ops
    ]

    # --- metrics + flags ---
    savings_rate = ((cur_inc - cur_exp) / cur_inc * 100.0) if cur_inc > 0 else 0.0
    trend_flags: List[str] = []
    if cur_bal >= 0:
        trend_flags.append("balance_positive_month")
    else:
        trend_flags.append("balance_negative_month")
    if delta_pct(cur_exp, prev_exp) is not None and delta_pct(cur_exp, prev_exp) > 5:
        trend_flags.append("expense_up_mom")

    payload: Dict[str, Any] = {
        "report_type": "budget",
        "period": "anchor_month",
        "metrics": {
            "anchor_month": float(int(anchor.year * 100 + anchor.month)),
            "window_months": float(window_months),
            "income_month": cur_inc,
            "expense_month": cur_exp,
            "balance_month": cur_bal,
            "savings_rate_month_pct": savings_rate,
            "coverage_months": float(coverage_months),
        },
        "trend_flags": trend_flags,
        "anomalies": anomalies,
        "series": [
            {"name": "Доходы по месяцам", "points": points_income, "unit": "RUB"},
            {"name": "Расходы по месяцам", "points": points_expense, "unit": "RUB"},
            {"name": "Сальдо по месяцам", "points": points_balance, "unit": "RUB"},
        ],
        "breakdowns": breakdowns or None,
        "comparisons": comparisons or None,
        "notes": "server_built_safe_payload_only",
    }
    return payload


def parse_budget_payload_options(req: Dict[str, Any]) -> BudgetPayloadOptions:
    """
    Утилита: пытается вытащить параметры построения payload из запроса (без ломания старого контракта).
    """
    anchor = _parse_anchor_month(req.get("anchor_month"))
    if not anchor:
        anchor = date.today().replace(day=1)
    window = int(req.get("window_months") or 72)
    uid = req.get("user_id")
    return BudgetPayloadOptions(anchor_month=anchor, window_months=window, user_id=uid)

