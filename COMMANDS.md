# 🚀 PVLFamily: Шпаргалка команд

Этот файл содержит все необходимые команды для разработки, тестирования и деплоя проекта PVLFamily.

> **⚠️ Важно:** Перед использованием команд убедитесь, что в корне проекта существует файл `.env_commands` с вашими персональными настройками (пути, IP-адреса, ключи). Этот файл не должен попадать в репозиторий.

---

## 🏠 Локальная разработка (Mac)

### 1. Запуск локального сервера
Запускает сервер в режиме разработки с авто-перезагрузкой при изменении кода.
```bash
cd $LOCAL_PROJECT_PATH/backend
source $LOCAL_VENV_PATH/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. Запуск автотестов
Проверяет весь функционал перед коммитом.
```bash
cd $LOCAL_PROJECT_PATH/backend
source $LOCAL_VENV_PATH/bin/activate
pytest tests/ -v
```

### 3. Проверка здоровья (Health Check)
Убедитесь, что локальный сервер отвечает.
```bash
curl http://localhost:8000/health
```

### 4. Открытие документации API (Swagger)
Откройте в браузере:
> http://localhost:8000/docs

---

## ☁️ Удаленный сервер (Cloud.ru)

**Переменные из `.env_commands`:** `REMOTE_IP`, `REMOTE_USER`, `REMOTE_SSH_KEY`

### 1. Проверка статуса сервиса
Показывает, запущен ли сервис `$REMOTE_SERVICE_NAME`.
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo systemctl status $REMOTE_SERVICE_NAME --no-pager -l"
```

### 2. Просмотр последних логов
Выводит последние 50 строки лога для отладки ошибок.
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo journalctl -u $REMOTE_SERVICE_NAME -n 50 --no-pager"
```

### 3. Перезапуск сервиса
Применяет изменения после обновления кода.
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo systemctl restart $REMOTE_SERVICE_NAME"
```

### 4. Проверка здоровья удаленного сервера
```bash
curl http://$REMOTE_IP:8000/health
```

### 5. Открытие документации API (Swagger)
Откройте в браузере:
> http://$REMOTE_IP:8000/docs

---

## 🔄 Деплой и обновление

### Вариант А: Полный скрипт (Рекомендуется)
Автоматически тестирует, коммитит и обновляет сервер.
```bash
cd $LOCAL_PROJECT_PATH
./deploy.sh
```

### Вариант Б: Ручное обновление
Если нужно просто подтянуть изменения на сервере без локальных тестов.
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "
cd $REMOTE_APP_ROOT
git pull
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart $REMOTE_SERVICE_NAME
"
```

---

## 🛠 Полезные утилиты

### Вход на сервер в интерактивном режиме
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP
```

### Копирование файла на сервер
```bash
scp -i $REMOTE_SSH_KEY /путь/к/файлу $REMOTE_USER@$REMOTE_IP:$REMOTE_APP_DIR/
```

### Перезагрузка виртуальной машины (если зависла)
*Выполняется в панели управления Cloud.ru или через консоль:*
```bash
ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo reboot"
```


### Команда запуска загрузки истории из загрузок на сервер с очисткой БД

```bash
scp -i $REMOTE_SSH_KEY ~/Downloads/history.csv $REMOTE_USER@$REMOTE_IP:$REMOTE_APP_DIR/ && ssh -i $REMOTE_SSH_KEY $REMOTE_USER@$REMOTE_IP "cd $REMOTE_APP_DIR && ./venv/bin/python import_history.py"
```

### Команда локального запуска загрузки истории в БД с ее очисткой

```bash
cd $LOCAL_PROJECT_PATH/backend
python import_history.py
```

---

## 📝 Правила разработки и безопасности

1. **Работа с данными**:
   - Никогда не коммитьте файлы `.env`, `.env_commands` или базы данных (`*.db`, `*.sqlite`).
   - Все секреты (ключи, пароли) храните только в переменных окружения.
   - При выводе логов или результатов команд скрывайте чувствительные данные (`***`).

2. **Код и архитектура**:
   - **Backend**: Все эндпоинты создания/изменения данных должны проверять авторизацию (`Depends(get_current_user)`).
   - **История пользователей**: При создании записей (транзакции, события, логи) обязательно сохраняйте `creator_name_snapshot` — имя пользователя на момент создания. Это нужно, чтобы при удалении пользователя история не терялась.
   - **Frontend (iOS)**: Используйте новый синтаксис `onChange` (с двумя параметрами `oldValue, newValue`) для совместимости с iOS 17+. Избегайте предупреждений компилятора.

3. **Синхронизация**:
   - Основной источник истины — локальный репозиторий на Mac.
   - GitHub используется как резервная копия и для истории изменений.
   - Облачный сервер обновляется только через скрипты деплоя или `git pull`.

4. **Тестирование**:
   - Перед любым деплоем запускайте локальные тесты (`pytest`).
   - Проверяйте здоровье сервера (`/health`) после обновления.