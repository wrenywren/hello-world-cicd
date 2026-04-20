import pytest
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_hello_world_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_hello_world_returns_correct_string(client):
    response = client.get("/")
    assert response.data.decode("utf-8") == "Hello World\n"


def test_health_check_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_health_check_returns_ok(client):
    response = client.get("/health")
    assert response.data.decode("utf-8") == "OK\n"
