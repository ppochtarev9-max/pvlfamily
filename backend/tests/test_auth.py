ADMIN_HEADERS = {"X-Admin-Token": "test-admin-token"}


def test_get_users_requires_admin(client, test_user):
    headers = {"Authorization": f"Bearer {test_user['access_token']}"}
    r = client.get("/auth/users", headers=headers)
    assert r.status_code == 403


def test_get_users_admin_allowed(client, make_user_admin_token):
    headers = {"Authorization": f"Bearer {make_user_admin_token}"}
    r = client.get("/auth/users", headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list)
    assert len(body) >= 1


def test_get_members_for_any_user(client, test_user):
    headers = {"Authorization": f"Bearer {test_user['access_token']}"}
    r = client.get("/auth/users/members", headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data, list)
    names = {x["name"] for x in data}
    assert test_user["name"] in names


def test_me_endpoint(client, test_user):
    headers = {"Authorization": f"Bearer {test_user['access_token']}"}
    r = client.get("/auth/me", headers=headers)
    assert r.status_code == 200
    j = r.json()
    assert j["user_id"]
    assert j["name"] == test_user["name"]
    assert "is_admin" in j


def test_admin_create_and_login_success(client):
    create_resp = client.post(
        "/auth/admin/users",
        json={"name": "NewUserTest", "password": "Password123", "must_reset_password": False},
        headers=ADMIN_HEADERS,
    )
    assert create_resp.status_code in [200, 201]

    response = client.post("/auth/login", json={
        "name": "NewUserTest",
        "password": "Password123"
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["name"] == "NewUserTest"
    assert data["force_password_reset"] is False

def test_login_success(client, test_user):
    response = client.post("/auth/login", json={
        "name": test_user["name"],
        "password": test_user["password"]
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "is_admin" in data
    assert data["is_admin"] is False

def test_login_empty_name_or_password(client):
    # Проверка на пустое имя (должно быть 400)
    response = client.post("/auth/login", json={
        "name": "",
        "password": "Password123"
    })
    assert response.status_code == 400

    response2 = client.post("/auth/login", json={
        "name": "TestUser",
        "password": ""
    })
    assert response2.status_code == 400

def test_login_invalid_credentials(client):
    response = client.post("/auth/login", json={
        "name": "NoSuchUser",
        "password": "WrongPass123"
    })
    assert response.status_code == 401

def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"