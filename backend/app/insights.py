from fastapi import APIRouter, Depends, Request
import logging

from . import models, schemas
from .auth import get_current_user
from .insights_service import InsightsService
from .rate_limit import limiter
from .budget_ai_payload import build_budget_safe_payload, parse_budget_payload_options

router = APIRouter()
service = InsightsService()
logger = logging.getLogger("PVLFamily.Insights")


@router.post("/budget", response_model=schemas.InsightResponse)
@limiter.limit("15/minute")
def budget_insight(
    request: Request,
    req: schemas.InsightRequest,
    current_user: models.User = Depends(get_current_user),
):
    logger.info(
        "[INSIGHTS] budget request user_id=%s provider=%s period=%s",
        current_user.id,
        req.provider or "default",
        req.payload.period,
    )
    payload_dict = req.payload.model_dump()

    # Режим "агрегаты с backend": если пришли параметры построения окна или явная пометка.
    wants_server_payload = bool(req.anchor_month or req.window_months or req.user_id) or (
        (req.payload.notes or "").strip().lower() in {"server", "server_build", "server_built"}
    )
    if wants_server_payload:
        opts = parse_budget_payload_options(
            {
                "anchor_month": req.anchor_month,
                "window_months": req.window_months,
                "user_id": req.user_id,
            }
        )
        # Безопасность: не-админ не может читать чужого user_id.
        effective_user_id = opts.user_id
        if effective_user_id is not None and (not current_user.is_admin) and effective_user_id != current_user.id:
            effective_user_id = current_user.id

        from .database import get_db  # локальный импорт чтобы не плодить зависимости в модуле

        # limiter уже использует request; здесь нам нужен Session.
        # FastAPI не даёт нам Depends(get_db) в этой сигнатуре без изменения, поэтому создаём сессию вручную.
        # (Путь безопасный, т.к. тот же engine/sessionmaker)
        db_gen = get_db()
        db = next(db_gen)
        try:
            payload_dict = build_budget_safe_payload(
                db,
                anchor_month=opts.anchor_month,
                window_months=opts.window_months,
                user_id=effective_user_id,
            )
        finally:
            try:
                next(db_gen)
            except StopIteration:
                pass

    if req.question:
        payload_dict["question"] = req.question.strip()

    result = service.generate(payload_dict, req.provider)
    logger.info(
        "[INSIGHTS] budget response provider=%s confidence=%.2f",
        result.provider,
        result.confidence,
    )
    return schemas.InsightResponse(
        provider=result.provider,
        summary_today=result.summary_today,
        summary_month=result.summary_month,
        bullets=result.bullets,
        risk_flags=result.risk_flags,
        confidence=result.confidence,
    )


@router.post("/tracker", response_model=schemas.InsightResponse)
@limiter.limit("15/minute")
def tracker_insight(
    request: Request,
    req: schemas.InsightRequest,
    current_user: models.User = Depends(get_current_user),
):
    logger.info(
        "[INSIGHTS] tracker request user_id=%s provider=%s period=%s",
        current_user.id,
        req.provider or "default",
        req.payload.period,
    )
    result = service.generate(req.payload.model_dump(), req.provider)
    logger.info(
        "[INSIGHTS] tracker response provider=%s confidence=%.2f",
        result.provider,
        result.confidence,
    )
    return schemas.InsightResponse(
        provider=result.provider,
        summary_today=result.summary_today,
        summary_month=result.summary_month,
        bullets=result.bullets,
        risk_flags=result.risk_flags,
        confidence=result.confidence,
    )
