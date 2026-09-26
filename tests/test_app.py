import tempfile
from pathlib import Path
from backend.app import create_app

def make_client():
    temp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    temp.close()
    app = create_app({
        "TESTING": True,
        "DATABASE": temp.name,
        "SECRET_KEY": "test-secret"
    })
    return app.test_client(), Path(temp.name)

def login(client):
    return client.post(
        "/api/login",
        json={"username": "admin", "password": "ChangeMe123!"}
    )

def test_health():
    client, path = make_client()
    try:
        response = client.get("/health")
        assert response.status_code == 200
        assert response.get_json()["status"] == "healthy"
    finally:
        path.unlink(missing_ok=True)

def test_creators_seeded():
    client, path = make_client()
    try:
        response = client.get("/api/creators")
        assert response.status_code == 200
        assert len(response.get_json()) == 3
    finally:
        path.unlink(missing_ok=True)

def test_crud_requires_authentication_and_then_works():
    client, path = make_client()
    try:
        response = client.post(
            "/api/creators",
            json={"name": "Demo", "platform": "YouTube", "followers": 1000}
        )
        assert response.status_code == 401

        assert login(client).status_code == 200

        created = client.post(
            "/api/creators",
            json={"name": "Demo", "platform": "YouTube", "followers": 1000}
        )
        assert created.status_code == 201
        creator_id = created.get_json()["id"]

        updated = client.put(
            f"/api/creators/{creator_id}",
            json={"name": "Demo", "platform": "YouTube", "followers": 2000}
        )
        assert updated.status_code == 200
        assert updated.get_json()["followers"] == 2000

        deleted = client.delete(f"/api/creators/{creator_id}")
        assert deleted.status_code == 200

        missing = client.get(f"/api/creators/{creator_id}")
        assert missing.status_code == 404
    finally:
        path.unlink(missing_ok=True)

def test_invalid_login():
    client, path = make_client()
    try:
        response = client.post(
            "/api/login",
            json={"username": "admin", "password": "wrong"}
        )
        assert response.status_code == 401
    finally:
        path.unlink(missing_ok=True)
