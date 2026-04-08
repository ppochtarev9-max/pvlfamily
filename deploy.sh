#!/bin/bash
# --- ЗАГРУЗКА КОНФИГУРАЦИИ ---
# Скрипт строго зависит от файла .env_commands в корне проекта.
# Все чувствительные данные и пути должны быть определены там.
if [ ! -f ".env_commands" ]; then
    echo "❌ ОШИБКА: Файл .env_commands не найден в текущей директории."
    echo "   Создайте файл .env_commands и заполните необходимые переменные:"
    echo "   REMOTE_USER, REMOTE_IP, REMOTE_SSH_KEY, REMOTE_APP_DIR, REMOTE_SERVICE_NAME"
    exit 1
fi
 source .env_commands
echo "✅ Конфигурация загружена из .env_commands"
# --- ПРОВЕРКА ОБЯЗАТЕЛЬНЫХ ПЕРЕМЕННЫХ ---
REQUIRED_VARS=("REMOTE_USER" "REMOTE_IP" "REMOTE_SSH_KEY" "REMOTE_APP_DIR" "REMOTE_SERVICE_NAME")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
T        echo "❌ ОШИБКА: Переменная $var не задана в файле .env_commands"
        exit 1
    fi
done
# Проверка существования SSH-ключа
if [ ! -f "$REMOTE_SSH_KEY" ]; then
    echo "❌ ОШИБКА: SSH-ключ не найден по пути: $REMOTE_SSH_KEY"
    echo "   Проверьте значение переменной REMOTE_SSH_KEY в файле .env_commands"
    exit 1
fi
COMMIT_MESSAGE="${1:-Auto-update: $(date '+%Y-%m-%d %H:%M')}"
echo "🚀 Начало процесса деплоя..."
echo "🔑 Используем SSH-ключ: $REMOTE_SSH_KEY"
echo "📡 Сервер: $REMOTE_USER@$REMOTE_IP"
echo "📂 Путь на сервере: $REMOTE_APP_DIR"
echo "🛠 Сервис: $REMOTE_SERVICE_NAME"
# 1. Локальные тесты
# Примечание: Пути локальной виртуалки берутся из LOCAL_VENV_PATH, если он задан, иначе предполагается стандартная структура
echo "🧪 1. Запуск локальных тестов..."
cd backend
if [ -n "$LOCAL_VENV_PATH" ] && [ -d "$LOCAL_VENV_PATH" ]; then
    VENV_ACTIVATE="$LOCAL_VENV_PATH/bin/activate"
elif [ -d "venv" ]; then
    VENV_ACTIVATE="venv/bin/activate"
else
    echo "⚠️ Локальная виртуальная среда не найдена. Пропускаем активацию для тестов (или используем системную)."
    VENV_ACTIVATE=""
fi
if [ -n "$VENV_ACTIVATE" ]; then
    source "$VENV_ACTIVATE"
fi
pytest tests/ -v
TEST_RESULT=$?
if [ -n "$VENV_ACTIVATE" ]; then
    deactivate
fi
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
echo "☁️ 3. Обновление кода на сервере $REMOTE_IP..."
# Определение пути к venv на сервере (проверка наличия папки .venv или venv в корне приложения)
# Мы формируем команду динамически внутри heredoc, используя переменные окружения
ssh -i "$REMOTE_SSH_KEY" "$REMOTE_USER@$REMOTE_IP" << ENDSSH
set -e  # Выход при ошибке
cd $REMOTE_APP_ROOT
git pull origin main
# Определение пути к python/venv на сервере
SERVER_VENV=""
if [ -d ".venv" ]; then
    SERVER_VENV=".venv"
elif [ -d "venv" ]; then
    SERVER_VENV="venv"
fi
if [ -n "\$SERVER_VENV" ] && [ -f "requirements.txt" ]; then
    echo "Обновление зависимостей в \$SERVER_VENV..."
    "\$SERVER_VENV/bin/pip" install -r requirements.txt --quiet
elif [ -f "requirements.txt" ]; then
    echo "⚠️ requirements.txt найден, но виртуальная среда (.venv или venv) не обнаружена."
fi
echo "Перезапуск сервиса $REMOTE_SERVICE_NAME..."
sudo systemctl restart $REMOTE_SERVICE_NAME
sleep 2
sudo systemctl status $REMOTE_SERVICE_NAME --no-pager
ENDSSH
if [ $? -eq 0 ]; then
    echo "✅ Сервер обновлен и перезапущен!"
    # 4. Финальная проверка здоровья (если задан эндпоинт, иначе пропускаем)
    # Можно добавить HEALTH_ENDPOINT в .env_commands при необходимости
    if [ -n "$HEALTH_ENDPOINT" ]; then
        echo "🏥 4. Проверка здоровья сервиса..."
        sleep 3
        if curl -s "$HEALTH_ENDPOINT" | grep -q "ok"; then
            echo "🎉 Деплой успешно завершен! Сервис работает."
        else
            echo "⚠️ Сервис запущен, но ответ от $HEALTH_ENDPOINT не получен. Проверьте логи."
        fi
    else
        echo "🎉 Деплой успешно завершен! (Проверка здоровья пропущена, HEALTH_ENDPOINT не задан)"
    fi
else
    echo "❌ Ошибка при обновлении сервера."
    exit 1
fi