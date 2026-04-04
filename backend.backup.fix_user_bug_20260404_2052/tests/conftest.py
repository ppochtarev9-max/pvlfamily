import pytest
import os
import tempfile
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.database import Base, get_db
from app.main import app

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
def test_user(client):
    user_data = {"name": "TestUser"}
    response = client.post("/auth/login", json=user_data)
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