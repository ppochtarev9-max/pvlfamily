# 🚀 PVLFamily: Шпаргалка команд

Этот файл содержит все необходимые команды для разработки, тестирования и деплоя проекта PVLFamily.

---

## 🏠 Локальная разработка (Mac)

### 1. Запуск локального сервера
Запускает сервер в режиме разработки с авто-перезагрузкой при изменении кода.
```bash
cd /Users/Pavel/PVLFamily/backend
source venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. Запуск автотестов
Проверяет весь функционал перед коммитом.
```bash
cd /Users/Pavel/PVLFamily/backend
source venv/bin/activate
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

**IP:** `213.171.28.80`  
**Пользователь:** `user1`  
**Ключ:** `~/.ssh/pvl_server_key`

### 1. Проверка статуса сервиса
Показывает, запущен ли сервис `pvlfamily`.
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "sudo systemctl status pvlfamily --no-pager -l"
```

### 2. Просмотр последних логов
Выводит последние 50 строки лога для отладки ошибок.
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "sudo journalctl -u pvlfamily -n 50 --no-pager"
```

### 3. Перезапуск сервиса
Применяет изменения после обновления кода.
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "sudo systemctl restart pvlfamily"
```

### 4. Проверка здоровья удаленного сервера
```bash
curl http://213.171.28.80:8000/health
```

### 5. Открытие документации API (Swagger)
Откройте в браузере:
> http://213.171.28.80:8000/docs

---

## 🔄 Деплой и обновление

### Вариант А: Полный скрипт (Рекомендуется)
Автоматически тестирует, коммитит и обновляет сервер.
```bash
cd /Users/Pavel/PVLFamily
./deploy.sh
```

### Вариант Б: Ручное обновление
Если нужно просто подтянуть изменения на сервере без локальных тестов.
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "
cd ~/pvl_app
git pull
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart pvlfamily
"
```

---

## 🛠 Полезные утилиты

### Вход на сервер в интерактивном режиме
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80
```

### Копирование файла на сервер
```bash
scp -i ~/.ssh/pvl_server_key /путь/к/файлу user1@213.171.28.80:~/pvl_app/backend/
```

### Перезагрузка виртуальной машины (если зависла)
*Выполняется в панели управления Cloud.ru или через консоль:*
```bash
ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "sudo reboot"
```


Команда запуска загрузки истории из загрузок на сервер с очисткой БД

scp -i ~/.ssh/pvl_server_key ~/Downloads/history.csv user1@213.171.28.80:~/pvl_app/backend/ && ssh -i ~/.ssh/pvl_server_key user1@213.171.28.80 "cd ~/pvl_app/backend && ./venv/bin/python import_history.py"

Команда локального запуска загрузки истории в БД с ее очисткой

cd backend
python import_history.py