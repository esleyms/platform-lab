import pytest
from fastapi.testclient import TestClient

from platform_api.config import Settings
from platform_api.main import create_app
from platform_api.repository import InMemoryRepository


@pytest.fixture
def repo() -> InMemoryRepository:
    return InMemoryRepository()


def make_client(repo: InMemoryRepository, **overrides) -> TestClient:
    settings = Settings(database_url=None, version="test", **overrides)
    return TestClient(create_app(settings, repo))


def test_healthz_does_not_depend_on_database(repo):
    repo.healthy = False
    with make_client(repo) as client:
        assert client.get("/healthz").status_code == 200


def test_readyz_reflects_database_state(repo):
    with make_client(repo) as client:
        assert client.get("/readyz").status_code == 200
        repo.healthy = False
        assert client.get("/readyz").status_code == 503


def test_create_and_get_item(repo):
    with make_client(repo) as client:
        created = client.post("/api/items", json={"name": "kind", "description": "cluster local"})
        assert created.status_code == 201
        item_id = created.json()["id"]

        fetched = client.get(f"/api/items/{item_id}")
        assert fetched.status_code == 200
        assert fetched.json()["name"] == "kind"

        assert [i["id"] for i in client.get("/api/items").json()] == [item_id]


def test_get_missing_item_returns_404(repo):
    with make_client(repo) as client:
        assert client.get("/api/items/999").status_code == 404


def test_validation_rejects_empty_name(repo):
    with make_client(repo) as client:
        assert client.post("/api/items", json={"name": ""}).status_code == 422


def test_write_requires_token_when_configured(repo):
    with make_client(repo, api_token="s3cret") as client:
        assert client.post("/api/items", json={"name": "x"}).status_code == 401
        ok = client.post(
            "/api/items", json={"name": "x"}, headers={"Authorization": "Bearer s3cret"}
        )
        assert ok.status_code == 201
        # leitura continua pública
        assert client.get("/api/items").status_code == 200


def test_fault_injection_returns_500(repo):
    with make_client(repo, fault_error_rate=1.0) as client:
        assert client.get("/api/items").status_code == 500
        assert client.get("/healthz").status_code == 200


def test_metrics_use_route_template(repo):
    with make_client(repo) as client:
        client.get("/api/items/42")
        body = client.get("/metrics").text
        assert 'route="/api/items/{item_id}"' in body
        assert 'status="404"' in body
        assert "http_request_duration_seconds_bucket" in body
        assert 'app_info{version="test"} 1.0' in body
