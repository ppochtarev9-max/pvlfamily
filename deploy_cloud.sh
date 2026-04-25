#!/usr/bin/env bash
set -euo pipefail

# Быстрый деплой на облако после git push:
# - подтянуть код на сервере
# - обновить python-зависимости
# - перезапустить systemd-сервис
# - показать короткий статус

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -f ".env_commands" ]]; then
  echo "❌ Файл .env_commands не найден в корне проекта."
  exit 1
fi

# shellcheck disable=SC1091
source .env_commands

required_vars=("REMOTE_USER" "REMOTE_IP" "REMOTE_SSH_KEY" "REMOTE_APP_ROOT" "REMOTE_SERVICE_NAME")
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Переменная $var не задана в .env_commands"
    exit 1
  fi
done

if [[ ! -f "$REMOTE_SSH_KEY" ]]; then
  echo "❌ SSH-ключ не найден: $REMOTE_SSH_KEY"
  exit 1
fi

echo "☁️ Деплой на $REMOTE_USER@$REMOTE_IP ($REMOTE_APP_ROOT)"

ssh -i "$REMOTE_SSH_KEY" "$REMOTE_USER@$REMOTE_IP" 'bash -lc "
set -e
cd '"$REMOTE_APP_ROOT"'
git pull --ff-only
cd backend
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart '"$REMOTE_SERVICE_NAME"'
sudo systemctl status '"$REMOTE_SERVICE_NAME"' --no-pager -l | sed -n \"1,20p\"
"'

echo "✅ Облачный деплой завершен."
