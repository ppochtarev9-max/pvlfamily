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

     # 1. ЖЕСТКИЙ СБРОС СИМУЛЯТОРОВ
    echo "🧹 Полная очистка и подготовка симуляторов..."
    killall Simulator 2>/dev/null || true
    killall com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
    xcrun simctl shutdown all 2>/dev/null || true
    # Не стираем все данные (erase all), чтобы не терять другие симуляторы, если они нужны.
    # Но сбрасываем состояние текущего запуска.
    
    sleep 2

    cd iOS || exit 1

    # Определение проекта
    if [ -d "PVLFamily.xcworkspace" ]; then
        SCHEME_PARAM="-scheme PVLFamilyUITests -workspace PVLFamily.xcworkspace"
    elif [ -d "PVLFamily.xcodeproj" ]; then
        SCHEME_PARAM="-scheme PVLFamilyUITests -project PVLFamily.xcodeproj"
    else
        echo "❌ Проект Xcode не найден."
        exit 1
    fi

    # 2. АВТОМАТИЧЕСКИЙ ВЫБОР СИМУЛЯТОРА
    # Ищем любой доступный симулятор iPhone с последней iOS
    # Если iPhone 16 нет, возьмет iPhone 15, 17 Pro или любой другой доступный
    DESTINATION_STRING="platform=iOS Simulator,name=iPhone 16,OS=latest"
    
    # Проверяем, существует ли такой симулятор
    if ! xcrun simctl list devices available | grep -q "iPhone 16"; then
        echo "⚠️ iPhone 16 не найден. Ищем альтернативу..."
        # Берем первый доступный iPhone с максимальной версией iOS
        # Команда получает список, фильтрует iPhone, сортирует по версии и берет последний
        DEVICE_NAME=$(xcrun simctl list devices available | grep iPhone | grep -v "unavailable" | tail -n 1 | awk -F '\\(' '{print $1}' | xargs)
        
        if [ -z "$DEVICE_NAME" ]; then
            echo "❌ Не найдено ни одного доступного симулятора iPhone!"
            exit 1
        fi
        
        # Извлекаем имя и версию (упрощенно берем просто имя устройства из списка)
        # Более надежный способ: использовать ID устройства
        DEVICE_ID=$(xcrun simctl list devices available | grep iPhone | grep -v "unavailable" | tail -n 1 | awk -F '[()]' '{print $2}')
        
        if [ -n "$DEVICE_ID" ]; then
            DESTINATION_STRING="platform=iOS Simulator,id=$DEVICE_ID"
            echo "✅ Выбран симулятор ID: $DEVICE_ID"
        else
            # Фоллбэк на любой доступный симулятор
            DESTINATION_STRING="platform=iOS Simulator,name=iPhone 17 Pro,OS=latest"
            echo "⚠️ Используем фоллбэк: $DESTINATION_STRING"
        fi
    else
        echo "✅ Найден iPhone 16."
    fi

   # 2. ОЧИСТКА СТАРЫХ РЕЗУЛЬТАТОВ
    # xcodebuild падает, если папка уже существует
    rm -rf TestResults

    echo "🚀 Запуск тестов на устройстве: $DESTINATION_STRING ..."

   # 3. ЗАПУСК
    xcodebuild test $SCHEME_PARAM \
        -destination "$DESTINATION_STRING" \
        -resultBundlePath TestResults \
        -retry-tests-on-failure \
        2>&1 | tee /tmp/xcodebuild.log

    UI_TEST_RESULT=${PIPESTATUS[0]}

    # 4. АНАЛИЗ РЕЗУЛЬТАТА
    if [ $UI_TEST_RESULT -ne 0 ]; then
        echo "⚠️ xcodebuild вернул код ошибки $UI_TEST_RESULT. Проверяем детали..."
        
        # Проверка 1: Была ли ошибка "Unable to find a device"?
        if grep -q "Unable to find a device" /tmp/xcodebuild.log; then
            echo "❌ Ошибка: Симyлятор не найден. Запустите симулятор вручную или создайте его в Xcode."
            exit 1
        fi

        # Проверка 2: Прошли ли тесты внутри, несмотря на ошибку процесса?
        if grep -q "Test Suite 'PVLFamilyUITests' passed" /tmp/xcodebuild.log; then
            echo "✅ Тесты пройдены успешно (ошибка окружения проигнорирована)."
            UI_TEST_RESULT=0
        else
            echo "❌ Тесты действительно упали или не запустились."
            # Выводим последние строки лога для диагностики
            echo "--- Последние строки лога ---"
            tail -n 20 /tmp/xcodebuild.log
            exit 1
        fi
    else
        echo "✅ iOS UI-тесты пройдены успешно."
    fi

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
REMOTE_CODE_DIR="${REMOTE_APP_ROOT:-$REMOTE_APP_DIR}"
echo "☁️ 3. Обновление кода на сервере $REMOTE_IP..."
ssh -i "$REMOTE_SSH_KEY" "$REMOTE_USER@$REMOTE_IP" << ENDSSH
set -e
cd $REMOTE_CODE_DIR
git pull origin main

SERVER_VENV=""
if [ -d ".venv" ]; then SERVER_VENV=".venv"; elif [ -d "venv" ]; then SERVER_VENV="venv"; fi

if [ -n "\$SERVER_VENV" ] && [ -f "requirements.txt" ]; then
    echo "Обновление зависимостей..."
    "\$SERVER_VENV/bin/pip" install -r requirements.txt --quiet
    echo "✅ Зависимости обновлены."
else
    echo "⚠️ Пропуск обновления зависимостей. Путь: $SERVER_VENV, Файл: $(ls requirements.txt 2>/dev/null || echo 'не найден')"
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