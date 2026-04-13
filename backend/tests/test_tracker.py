import time
from datetime import datetime, timedelta, timezone
from app.models import BabyLog

def get_token(client, name):
    resp = client.post("/auth/login", json={"name": name})
    return resp.json()["access_token"]

def test_tracker_initial_status(client, test_user):
    """Проверка начального статуса: пользователь не спит"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.get("/tracker/status", headers=headers)
    assert response.status_code == 200
    data = response.json()
    
    assert data["is_sleeping"] is False
    assert data["current_sleep_id"] is None
    assert data["current_sleep_start"] is None
    # last_wake_up может быть None, если это первый вход

def test_start_sleep(client, test_user):
    """Тест начала сна: создание записи и обновление статуса"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # 1. Запускаем сон
    response = client.post("/tracker/logs", json={
        "event_type": "sleep",
        "start_time": datetime.now(timezone.utc).isoformat()
    }, headers=headers)
    
    assert response.status_code in [200, 201]
    log_data = response.json()
    assert log_data["event_type"] == "sleep"
    assert log_data["end_time"] is None
    
    # 2. Проверяем статус: теперь спим
    status_resp = client.get("/tracker/status", headers=headers)
    assert status_resp.status_code == 200
    status = status_resp.json()
    
    assert status["is_sleeping"] is True
    assert status["current_sleep_id"] == log_data["id"]
    assert status["current_sleep_start"] is not None

def test_finish_sleep(client, test_user):
    """Тест завершения сна: расчет длительности и смена статуса"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    start_time = datetime.now(timezone.utc)
    # Имитируем сон длительностью 2 минуты (для теста)
    end_time = start_time + timedelta(minutes=2)
    
    # 1. Создаем сон
    start_resp = client.post("/tracker/logs", json={
        "event_type": "sleep",
        "start_time": start_time.isoformat()
    }, headers=headers)
    assert start_resp.status_code in [200, 201]
    sleep_id = start_resp.json()["id"]
    
    # 2. Завершаем сон (в реальном API мы шлем PUT с end_time)
    finish_resp = client.put(f"/tracker/logs/{sleep_id}", json={
        "end_time": end_time.isoformat()
    }, headers=headers)
    
    assert finish_resp.status_code == 200
    finished_log = finish_resp.json()
    
    assert finished_log["end_time"] is not None
    assert finished_log["duration_minutes"] >= 2 # Должно быть около 2 минут
    
    # 3. Проверяем статус: больше не спим
    status_resp = client.get("/tracker/status", headers=headers)
    status = status_resp.json()
    assert status["is_sleeping"] is False
    assert status["current_sleep_id"] is None
    assert status["last_wake_up"] is not None

def test_quick_feed(client, test_user):
    """Тест быстрого кормления: мгновенное событие"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Эндпоинт может отличаться, проверяем стандартный POST logs
    now = datetime.now(timezone.utc).isoformat()
    response = client.post("/tracker/logs", json={
        "event_type": "feed",
        "start_time": now,
        "end_time": now,
        "note": "Quick feed test"
    }, headers=headers)
    
    assert response.status_code in [200, 201]
    data = response.json()
    assert data["event_type"] == "feed"
    assert data["duration_minutes"] == 0 # Мгновенное событие

def test_get_logs_history(client, test_user):
    """Тест получения истории событий"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Создаем тестовое событие
    client.post("/tracker/logs", json={
        "event_type": "sleep",
        "start_time": datetime.now(timezone.utc).isoformat()
    }, headers=headers)
    
    # Получаем список
    response = client.get("/tracker/logs", headers=headers)
    assert response.status_code == 200
    logs = response.json()
    
    assert isinstance(logs, list)
    assert len(logs) > 0
    # Проверяем, что последнее событие - наше
    assert logs[0]["event_type"] == "sleep"

def test_finish_non_existent_sleep(client, test_user):
    """Тест ошибки при попытке завершить несуществующий сон"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Пытаемся завершить сон с ID 99999
    response = client.put("/tracker/logs/99999", json={
        "end_time": datetime.now(timezone.utc).isoformat()
    }, headers=headers)
    
    # Должен вернуть 404
    assert response.status_code == 404

def test_delete_log(client, test_user):
    """Тест удаления записи"""
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Создаем запись
    create_resp = client.post("/tracker/logs", json={
        "event_type": "feed",
        "start_time": datetime.now(timezone.utc).isoformat(),
        "end_time": datetime.now(timezone.utc).isoformat()
    }, headers=headers)
    assert create_resp.status_code in [200, 201]
    log_id = create_resp.json()["id"]
    
    # Удаляем
    delete_resp = client.delete(f"/tracker/logs/{log_id}", headers=headers)
    assert delete_resp.status_code == 200
    
    # Проверяем, что удалена
    logs_resp = client.get("/tracker/logs", headers=headers)
    logs = logs_resp.json()
    ids = [log["id"] for log in logs]
    assert log_id not in ids