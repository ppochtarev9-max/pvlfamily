import json
import os
import time
import uuid
import logging
from dataclasses import dataclass
from typing import Dict, List, Optional, Protocol

import httpx


@dataclass
class InsightResult:
    provider: str
    summary_today: str
    summary_month: str
    bullets: List[str]
    risk_flags: List[str]
    confidence: float


class LLMProvider(Protocol):
    name: str

    def generate_insight(self, payload: Dict) -> InsightResult:
        ...

logger = logging.getLogger("PVLFamily.LLM")


def _extract_json(text: str) -> Dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text.replace("json\n", "", 1)
    return json.loads(text)


def _fallback_rule_based(payload: Dict, provider: str = "rule-based") -> InsightResult:
    report_type = payload.get("report_type", "report")
    period = payload.get("period", "period")
    flags = payload.get("trend_flags", []) or []
    anomalies = payload.get("anomalies", []) or []
    metrics = payload.get("metrics", {}) or {}

    today = f"Базовый вывод для {report_type}: данные получены за {period}."
    month = "Сводка периода сформирована без модели LLM."

    if "balance_positive" in flags:
        today = "Баланс остаётся положительным, краткосрочный тренд стабильный."
    if "expense_up" in flags:
        month = "Расходы растут относительно предыдущего периода, стоит проверить крупные категории."
    if anomalies:
        month += " Обнаружены выбросы, проверьте детали отчёта."

    bullet_metrics = [f"{k}: {v}" for k, v in list(metrics.items())[:3]]
    bullets = bullet_metrics if bullet_metrics else ["Недостаточно агрегатов для расширенного вывода."]
    risk_flags = ["anomaly_detected"] if anomalies else []
    confidence = 0.45 if anomalies else 0.55

    return InsightResult(
        provider=provider,
        summary_today=today,
        summary_month=month,
        bullets=bullets,
        risk_flags=risk_flags,
        confidence=confidence,
    )


class OpenAICompatibleProvider:
    def __init__(self, name: str, api_key: str, model: str, base_url: str):
        self.name = name
        self.api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.timeout = float(os.getenv("LLM_TIMEOUT_SECONDS", "20"))
        self.max_tokens = int(os.getenv("LLM_MAX_TOKENS", "500"))
        self.temperature = float(os.getenv("LLM_TEMPERATURE", "0.2"))

    def generate_insight(self, payload: Dict) -> InsightResult:
        if not self.api_key or not self.base_url or not self.model:
            logger.warning(
                "[LLM] %s fallback: missing config (api_key/base_url/model)",
                self.name,
            )
            return _fallback_rule_based(payload, provider=f"{self.name}-fallback")

        system_prompt = (
            "Ты аналитик финансов/режима сна. Верни СТРОГО JSON без markdown и без лишнего текста. "
            "Тебе придёт агрегированный safe_payload (metrics, trend_flags, anomalies, а также возможно series/breakdowns/comparisons). "
            "Поля ответа: summary_today (string), summary_month (string), bullets (string[]), "
            "risk_flags (string[]), confidence (number 0..1)."
        )
        user_prompt = json.dumps(payload, ensure_ascii=False)

        body = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "response_format": {"type": "json_object"},
        }

        try:
            logger.info("[LLM] %s request model=%s", self.name, self.model)
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(
                    f"{self.base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json=body,
                )
                resp.raise_for_status()
                data = resp.json()
                content = data["choices"][0]["message"]["content"]
                parsed = _extract_json(content)
            logger.info("[LLM] %s response OK", self.name)

            return InsightResult(
                provider=self.name,
                summary_today=str(parsed.get("summary_today", "")),
                summary_month=str(parsed.get("summary_month", "")),
                bullets=[str(x) for x in parsed.get("bullets", [])][:5],
                risk_flags=[str(x) for x in parsed.get("risk_flags", [])][:5],
                confidence=float(parsed.get("confidence", 0.5)),
            )
        except Exception as e:
            logger.error("[LLM] %s response error: %s", self.name, e)
            fallback = _fallback_rule_based(payload, provider=f"{self.name}-fallback")
            fallback.summary_month = f"LLM временно недоступен ({self.name}). Использован локальный fallback."
            fallback.bullets = [f"Ошибка провайдера: {type(e).__name__}"]
            fallback.confidence = 0.3
            return fallback


class GigaChatProvider:
    def __init__(self):
        self.name = "gigachat"
        self.auth_key = os.getenv("GIGACHAT_AUTH_KEY", "")
        self.scope = os.getenv("GIGACHAT_SCOPE", "GIGACHAT_API_PERS")
        self.model = os.getenv("GIGACHAT_MODEL", "GigaChat-2-Max")
        self.oauth_url = os.getenv("GIGACHAT_AUTH_URL", "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")
        self.api_url = os.getenv("GIGACHAT_API_URL", "https://gigachat.devices.sberbank.ru/api/v1/chat/completions")
        self.verify_ssl = os.getenv("GIGACHAT_VERIFY_SSL", "true").lower() in {"1", "true", "yes"}
        self.timeout = float(os.getenv("LLM_TIMEOUT_SECONDS", "20"))
        self.max_tokens = int(os.getenv("LLM_MAX_TOKENS", "500"))
        self.temperature = float(os.getenv("LLM_TEMPERATURE", "0.2"))
        self._access_token: Optional[str] = None
        self._expires_at_ms: int = 0

    def _get_token(self) -> Optional[str]:
        now_ms = int(time.time() * 1000)
        if self._access_token and now_ms < self._expires_at_ms - 60_000:
            logger.info("[LLM] gigachat oauth token cache hit")
            return self._access_token
        if not self.auth_key:
            return None

        headers = {
            "Authorization": f"Basic {self.auth_key}",
            "RqUID": str(uuid.uuid4()),
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        }
        data = {"scope": self.scope}

        with httpx.Client(timeout=self.timeout, verify=self.verify_ssl) as client:
            resp = client.post(self.oauth_url, headers=headers, data=data)
            resp.raise_for_status()
            body = resp.json()
        self._access_token = body.get("access_token")
        self._expires_at_ms = int(body.get("expires_at", 0) or 0)
        logger.info("[LLM] gigachat oauth token refreshed")
        return self._access_token

    def generate_insight(self, payload: Dict) -> InsightResult:
        try:
            token = self._get_token()
            if not token:
                logger.warning("[LLM] gigachat fallback: missing token")
                return _fallback_rule_based(payload, provider="gigachat-fallback")

            system_prompt = (
                "Ты аналитик финансов/режима сна. Верни СТРОГО JSON без markdown и без лишнего текста. "
                "Тебе придёт агрегированный safe_payload (metrics, trend_flags, anomalies, а также возможно series/breakdowns/comparisons). "
                "Поля ответа: summary_today (string), summary_month (string), bullets (string[]), "
                "risk_flags (string[]), confidence (number 0..1)."
            )
            user_prompt = json.dumps(payload, ensure_ascii=False)

            body = {
                "model": self.model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "n": 1,
                "stream": False,
                "max_tokens": self.max_tokens,
                "temperature": self.temperature,
                "repetition_penalty": 1,
                "update_interval": 0,
            }

            with httpx.Client(timeout=self.timeout, verify=self.verify_ssl) as client:
                resp = client.post(
                    self.api_url,
                    headers={
                        "Authorization": f"Bearer {token}",
                        "Content-Type": "application/json",
                        "Accept": "application/json",
                    },
                    json=body,
                )
                resp.raise_for_status()
                data = resp.json()
                content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            logger.info("[LLM] gigachat response OK")

            try:
                parsed = _extract_json(content)
                return InsightResult(
                    provider=self.name,
                    summary_today=str(parsed.get("summary_today", "")),
                    summary_month=str(parsed.get("summary_month", "")),
                    bullets=[str(x) for x in parsed.get("bullets", [])][:5],
                    risk_flags=[str(x) for x in parsed.get("risk_flags", [])][:5],
                    confidence=float(parsed.get("confidence", 0.5)),
                )
            except Exception:
                logger.warning("[LLM] gigachat response non-json; returning text fallback")
                # Если модель вернула текст вместо JSON, не роняем поток.
                return InsightResult(
                    provider=f"{self.name}-text",
                    summary_today="LLM вернул текстовый ответ без JSON-формата.",
                    summary_month=str(content)[:900],
                    bullets=[],
                    risk_flags=[],
                    confidence=0.35,
                )
        except Exception as e:
            logger.error("[LLM] gigachat response error: %s", e)
            err = str(e).lower()
            if "certificate_verify_failed" in err or "ssl" in err or "self-signed" in err:
                logger.error(
                    "[LLM] GigaChat TLS: нельзя проверить цепочку (часто на Linux/облаке). "
                    "Проверьте CA/время на сервере, либо укажите GIGACHAT_VERIFY_SSL=false в .env (как у себя на Mac) и перезапустите."
                )
            fallback = _fallback_rule_based(payload, provider="gigachat-fallback")
            fallback.summary_month = "GigaChat временно недоступен. Использован локальный fallback."
            fallback.bullets = [f"Ошибка провайдера: {type(e).__name__}"]
            fallback.confidence = 0.3
            return fallback


def make_provider(name: Optional[str]) -> LLMProvider:
    provider = (name or os.getenv("LLM_PROVIDER", "openai")).lower().strip()
    if provider == "auto":
        provider = os.getenv("LLM_FALLBACK_PROVIDER", "openai").lower().strip()

    if provider == "openai":
        return OpenAICompatibleProvider(
            name="openai",
            api_key=os.getenv("OPENAI_API_KEY", ""),
            model=os.getenv("OPENAI_MODEL", "gpt-4.1-mini"),
            base_url=os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1"),
        )
    if provider == "deepseek":
        return OpenAICompatibleProvider(
            name="deepseek",
            api_key=os.getenv("DEEPSEEK_API_KEY", ""),
            model=os.getenv("DEEPSEEK_MODEL", "deepseek-chat"),
            base_url=os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1"),
        )
    if provider == "qwen":
        return OpenAICompatibleProvider(
            name="qwen",
            api_key=os.getenv("QWEN_API_KEY", ""),
            model=os.getenv("QWEN_MODEL", "qwen-plus"),
            base_url=os.getenv("QWEN_BASE_URL", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
        )
    if provider == "anthropic":
        return OpenAICompatibleProvider(
            name="anthropic",
            api_key=os.getenv("ANTHROPIC_API_KEY", ""),
            model=os.getenv("ANTHROPIC_MODEL", "claude-3-5-sonnet-latest"),
            # Если Anthropic не в OpenAI-compatible режиме, лучше fallback до отдельного адаптера.
            base_url=os.getenv("ANTHROPIC_COMPAT_BASE_URL", ""),
        )
    if provider == "gigachat":
        return GigaChatProvider()

    return OpenAICompatibleProvider(name="rule-based", api_key="", model="", base_url="")
