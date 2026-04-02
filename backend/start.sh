#!/bin/bash
echo "🚀 Запуск PVLFamily API..."
# Активируем виртуальное окружение
source venv/bin/activate
# Запускаем сервер на всех интерфейсах
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
