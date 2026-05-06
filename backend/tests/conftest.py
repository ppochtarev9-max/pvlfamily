import pytest
import os
import tempfile
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.database import Base, get_db

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("ADMIN_TOKEN", "test-admin-token")
os.environ.setdefault("ADMIN_NAME", "Паша")
os.environ.setdefault("ADMIN_INITIAL_PASSWORD", "Temporary123")

from app.main import app
from app import rate_limit, models as app_models

# Создаем временный файл для БД в системе (избегаем проблем с правами)
db_fd, db_path = tempfile.mkstemp(suffix=".db")

SQLALCHEMY_DATABASE_URL = f"sqlite:///{db_path}"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(scope="session", autouse=True)
def disable_rate_limits_for_tests():
    rate_limit.limiter.enabled = False
    app.state.limiter.enabled = False
    yield
    rate_limit.limiter.enabled = True
    app.state.limiter.enabled = True

@pytest.fixture(scope="function", autouse=True)
def setup_database():
    # Создаем таблицы перед каждым тестом
    Base.metadata.create_all(bind=engine)
    yield
    # Удаляем таблицы после теста (для чистоты)
    Base.metadata.drop_all(bind=engine)

@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c

@pytest.fixture
def make_user_admin_token(client, test_user):
    """Повышение TestUser до админа в тестовой БД и новый Bearer."""
    db = TestingSessionLocal()
    try:
        usr = db.query(app_models.User).filter(app_models.User.name == test_user["name"]).first()
        assert usr is not None
        usr.is_admin = True
        db.commit()
    finally:
        db.close()

    lg = client.post("/auth/login", json={"name": test_user["name"], "password": test_user["password"]})
    assert lg.status_code == 200
    return lg.json()["access_token"]


@pytest.fixture
def test_user(client):
    user_data = {"name": "TestUser", "password": "Password123"}
    create_resp = client.post(
        "/auth/admin/users",
        json={"name": user_data["name"], "password": user_data["password"], "must_reset_password": False},
        headers={"X-Admin-Token": "test-admin-token"},
    )
    assert create_resp.status_code in [200, 201, 409]
    response = client.post("/auth/login", json=user_data)
    token = response.json().get("access_token")
    user_data["access_token"] = token
    return user_data

# Очистка временного файла после всех тестов
@pytest.fixture(scope="session", autouse=True)
def cleanup():
    yield
    try:
        os.close(db_fd)
        if os.path.exists(db_path):
            os.remove(db_path)
    except Exception:
        pass