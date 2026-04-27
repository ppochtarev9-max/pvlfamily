# LLM quickstart (Qwen + GigaChat)

## 1) Заполни ключи в `.env`

Обязательные поля:

- `QWEN_API_KEY`
- `GIGACHAT_AUTH_KEY`

Остальные значения уже готовы под стандартные endpoint'ы.

## 2) Перезапусти backend

```bash
cd backend
source venv/bin/activate
uvicorn app.main:app --reload
```

## 3) Smoke test: budget insights

```bash
TOKEN="<твой_jwt_из_login>"

curl -s -X POST "http://127.0.0.1:8000/insights/budget" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "qwen",
    "payload": {
      "report_type": "budget",
      "period": "current_month",
      "metrics": {
        "balance_today": 338500,
        "income_month": 240000,
        "expense_month": 180000,
        "expense_delta_vs_prev_pct": 12.5
      },
      "trend_flags": ["balance_positive", "expense_up"],
      "anomalies": [{"type":"expense_spike_day","value":15000}],
      "notes": "safe_payload_only"
    }
  }'
```

Сменить провайдер:

- `"provider": "gigachat"`
- `"provider": "qwen"`

## 4) Что увидишь в iOS

На экранах:

- `BudgetAnalyticsHubView`
- `TrackerAnalyticsHubView`

появятся:

- `summary_today`
- `summary_month`
- подпись `LLM: <provider>`

Если ключ не заполнен/ошибка сети — останется локальный rule-based текст (без падения UI).
