#!/bin/bash
echo "🚀 Запуск PVLFamily API..."
source venv/bin/activate
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
