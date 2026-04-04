def test_register_success(client):
    # В твоей системе регистрация = вход по имени
    response = client.post("/auth/login", json={
        "name": "NewUserTest"
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["name"] == "NewUserTest"

def test_login_success(client, test_user):
    # Повторный вход тем же пользователем
    response = client.post("/auth/login", json={
        "name": test_user["name"]
    })
    assert response.status_code == 200
    assert "access_token" in response.json()

def test_login_empty_name(client):
    # Проверка на пустое имя (должно быть 400)
    response = client.post("/auth/login", json={
        "name": ""
    })
    assert response.status_code == 400

def test_register_duplicate(client, test_user):
    # В твоей системе повторный вход с тем же именем просто возвращает токен (это успех)
    # Поэтому проверяем, что система не падает и возвращает данные
    response = client.post("/auth/login", json={
        "name": test_user["name"]
    })
    assert response.status_code == 200
    assert response.json()["name"] == test_user["name"]

def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"