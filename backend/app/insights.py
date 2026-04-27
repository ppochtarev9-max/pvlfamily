from fastapi import APIRouter, Depends
import logging

from . import models, schemas
from .auth import get_current_user
from .insights_service import InsightsService

router = APIRouter()
service = InsightsService()
logger = logging.getLogger("PVLFamily.Insights")


@router.post("/budget", response_model=schemas.InsightResponse)
def budget_insight(
    req: schemas.InsightRequest,
    current_user: models.User = Depends(get_current_user),
):
    logger.info(
        "[INSIGHTS] budget request user_id=%s provider=%s period=%s",
        current_user.id,
        req.provider or "default",
        req.payload.period,
    )
    result = service.generate(req.payload.model_dump(), req.provider)
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
def tracker_insight(
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
