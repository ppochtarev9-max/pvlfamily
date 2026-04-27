from typing import Dict, Optional

from .llm_provider import InsightResult, make_provider


class InsightsService:
    def generate(self, payload: Dict, provider_name: Optional[str] = None) -> InsightResult:
        provider = make_provider(provider_name)
        return provider.generate_insight(payload)
