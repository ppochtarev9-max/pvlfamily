#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
SERVER_USER="user1"
SERVER_IP="213.171.28.80"

# Исправление пункта 10: Гибкий путь к SSH-ключу
# 1. Берем из переменной окружения SSH_KEY_PATH, если задана.
# 2. Иначе используем путь по умолчанию ~/.ssh/pvl_server_key.
# 3. Явно раскрываем ~ до $HOME для надежности.
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/pvl_server_key}"

# Проверка существования ключа
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ ОШИБКА: SSH-ключ не найден по пути: $SSH_KEY_PATH"
    echo "   Укажите правильный путь через переменную окружения: export SSH_KEY_PATH=/путь/к/ключу"
    exit 1
fi

PROJECT_PATH_REMOTE="~/pvl_app"
SERVICE_NAME="pvlfamily"
COMMIT_MESSAGE="${1:-Auto-update: $(date '+%Y-%m-%d %H:%M')}"

echo "🚀 Начало процесса деплоя..."
echo "🔑 Используем SSH-ключ: $SSH_KEY_PATH"

# 1. Локальные тесты
echo "🧪 1. Запуск локальных тестов..."
cd backend
source venv/bin/activate
pytest tests/ -v
TEST_RESULT=$?
deactivate

if [ $TEST_RESULT -ne 0 ]; then
    echo "❌ Локальные тесты не прошли! Деплой отменен."
    exit 1
fi
echo "✅ Локальные тесты пройдены."
cd ..

# 2. Git Commit & Push
echo "📦 2. Коммит и отправка в GitHub..."
git add .
git commit -m "$COMMIT_MESSAGE"
if [ $? -ne 0 ]; then
    echo "⚠️ Нет изменений для коммита или ошибка git."
else
    git push origin main
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка при push в GitHub. Проверьте соединение."
        exit 1
    fi
    echo "✅ Код отправлен в GitHub. CI-тесты запущены на стороне GitHub Actions."
fi

# 3. Обновление на сервере
echo "☁️ 3. Обновление кода на сервере $SERVER_IP..."

# Используем проверенный путь к ключу
ssh -i "$SSH_KEY_PATH" "$SERVER_USER@$SERVER_IP" << 'ENDSSH'
cd ~/pvl_app
git pull origin main

# Активация venv и установка зависимостей (если есть requirements.txt)
if [ -f "requirements.txt" ]; then
    ./venv/bin/pip install -r requirements.txt --quiet
fi

echo "Перезапуск сервиса $SERVICE_NAME..."
sudo systemctl restart $SERVICE_NAME
sleep 2
sudo systemctl status $SERVICE_NAME --no-pager
ENDSSH

if [ $? -eq 0 ]; then
    echo "✅ Сервер обновлен и перезапущен!"
    
    # 4. Финальная проверка здоровья
    echo "🏥 4. Проверка здоровья сервиса..."
    sleep 3 # Даем время на старт
    curl -s http://$SERVER_IP:8000/health | grep -q "ok"
    
    if [ $? -eq 0 ]; then
        echo "🎉 Деплой успешно завершен! Сервис работает."
    else
        echo "⚠️ Сервис запущен, но ответ /health не получен. Проверьте логи."
    fi
else
    echo "❌ Ошибка при обновлении сервера."
    exit 1
fi