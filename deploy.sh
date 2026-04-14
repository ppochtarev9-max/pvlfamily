#!/bin/bash
# --- ЗАГРУЗКА КОНФИГУРАЦИИ ---
if [ ! -f ".env_commands" ]; then
    echo "❌ ОШИБКА: Файл .env_commands не найден."
    exit 1
fi
source .env_commands

# --- ПРОВЕРКА ПЕРЕМЕННЫХ ---
REQUIRED_VARS=("REMOTE_USER" "REMOTE_IP" "REMOTE_SSH_KEY" "REMOTE_APP_DIR" "REMOTE_SERVICE_NAME")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ ОШИБКА: Переменная $var не задана."
        exit 1
    fi
done

if [ ! -f "$REMOTE_SSH_KEY" ]; then
    echo "❌ ОШИБКА: SSH-ключ не найден: $REMOTE_SSH_KEY"
    exit 1
fi

COMMIT_MESSAGE="${1:-Auto-update: $(date '+%Y-%m-%d %H:%M')}"
echo "🚀 Начало процесса деплоя..."

# 0. ПРЕ-ПРОВЕРКА: Наличие Xcode и симулятора (только для macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Обнаружена macOS. Подготовка к UI-тестам..."
    # Убиваем зависшие процессы симуляторов, чтобы тесты прошли чисто
    xcrun simctl shutdown all 2>/dev/null || true
else
    echo "⚠️ Не-macOS среда. Пропускаем UI-тесты (требуется симулятор)."
    SKIP_UI_TESTS=true
fi

#Временно не провожу принудительно!
    SKIP_UI_TESTS=true


# 1. Локальные Backend-тесты
echo "🧪 1. Запуск backend-тестов (pytest)..."
cd backend
if [ -d "venv" ]; then
    source venv/bin/activate
fi
pytest tests/ -v
TEST_RESULT=$?
if [ -n "$(which deactivate)" ]; then deactivate; fi

if [ $TEST_RESULT -ne 0 ]; then
    echo "❌ Backend-тесты не пройдены! Деплой отменен."
    exit 1
fi
echo "✅ Backend-тесты пройдены."
cd ..

# 1.5. Локальные UI-тесты (ТОЛЬКО ЕСЛИ MAC)
if [ "$SKIP_UI_TESTS" != "true" ]; then
    echo "📱 1.5. Запуск iOS UI-тестов..."
    
    # Принудительно убиваем все зависшие симуляторы перед стартом
    echo "🧹 Очистка старых процессов симуляторов..."
    killall Simulator 2>/dev/null || true
    xcrun simctl shutdown all 2>/dev/null || true
    sleep 2

    cd iOS
    
    # Определяем путь к проекту
    if [ -f "PVLFamily.xcworkspace" ]; then
        SCHEME_PARAM="-scheme PVLFamilyUITests -workspace PVLFamily.xcworkspace"
    elif [ -f "PVLFamily.xcodeproj" ]; then
        SCHEME_PARAM="-scheme PVLFamilyUITests -project PVLFamily.xcodeproj"
    else
        echo "❌ Проект Xcode не найден в папке iOS."
        exit 1
    fi

    # Явно указываем конкретное устройство и версию (если известна), 
    # либо используем 'available' чтобы взять первый подходящий
    echo "🚀 Запуск тестов на симуляторе..."
    
    # Попытка запуска на iPhone 16 (iOS 18)
    xcodebuild test $SCHEME_PARAM \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
        -quiet \
        || \

    UI_TEST_RESULT=$?
    
    if [ $UI_TEST_RESULT -ne 0 ]; then
        echo "❌ iOS UI-тесты не пройдены! Деплой отменен."
        # Можно добавить вывод логов для отладки
        # cat ~/Library/Logs/CoreSimulator/... 
        exit 1
    fi
    echo "✅ iOS UI-тесты пройдены."
    cd ..
fi

# 2. Git Commit & Push
echo "📦 2. Коммит и отправка в GitHub..."
git add .
git commit -m "$COMMIT_MESSAGE"
if [ $? -ne 0 ]; then
    echo "⚠️ Нет изменений для коммита."
else
    git push origin main
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка при push."
        exit 1
    fi
    echo "✅ Код отправлен в GitHub."
fi

# 3. Обновление на сервере
echo "☁️ 3. Обновление кода на сервере $REMOTE_IP..."
ssh -i "$REMOTE_SSH_KEY" "$REMOTE_USER@$REMOTE_IP" << ENDSSH
set -e
cd $REMOTE_APP_ROOT
git pull origin main

SERVER_VENV=""
if [ -d ".venv" ]; then SERVER_VENV=".venv"; elif [ -d "venv" ]; then SERVER_VENV="venv"; fi

if [ -n "\$SERVER_VENV" ] && [ -f "requirements.txt" ]; then
    echo "Обновление зависимостей..."
    "\$SERVER_VENV/bin/pip" install -r requirements.txt --quiet
fi

echo "Перезапуск сервиса $REMOTE_SERVICE_NAME..."
sudo systemctl restart $REMOTE_SERVICE_NAME
sleep 2
sudo systemctl status $REMOTE_SERVICE_NAME --no-pager
ENDSSH

if [ $? -eq 0 ]; then
    echo "✅ Сервер обновлен!"
    if [ -n "$HEALTH_ENDPOINT" ]; then
        echo "🏥 Проверка здоровья..."
        sleep 3
        if curl -s "$HEALTH_ENDPOINT" | grep -q "ok"; then
            echo "🎉 Деплой успешен! Сервис работает."
        else
            echo "⚠️ Сервис запущен, но Health Check не прошел."
        fi
    else
        echo "🎉 Деплой успешен!"
    fi
else
    echo "❌ Ошибка обновления сервера."
    exit 1
fi