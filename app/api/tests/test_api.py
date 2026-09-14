from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_items_crud() -> None:
    r = client.post("/items", json={"name": "trivy", "quantity": 1})
    assert r.status_code == 201
    item = r.json()

    r = client.get("/items")
    assert any(i["id"] == item["id"] for i in r.json())

    r = client.get(f"/items/{item['id']}")
    assert r.status_code == 200

    r = client.delete(f"/items/{item['id']}")
    assert r.status_code == 204

    r = client.get(f"/items/{item['id']}")
    assert r.status_code == 404


def test_validation_rejects_bad_payload() -> None:
    r = client.post("/items", json={"name": "", "quantity": -1})
    assert r.status_code == 422


def test_metrics_exposed() -> None:
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"http_request" in r.content
