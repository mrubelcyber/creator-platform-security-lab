import secrets
import tempfile
from pathlib import Path
from backend.app import create_app

TEST_ADMIN_PASSWORD = secrets.token_urlsafe(16)


def make_client():
    temp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    temp.close()
    app = create_app({
        "TESTING": True,
        "DATABASE": temp.name,
        "SECRET_KEY": "test-secret",
        "ADMIN_INITIAL_PASSWORD": TEST_ADMIN_PASSWORD,
    })
    return app.test_client(), Path(temp.name)

def login(client):
    return client.post(
        "/api/login",
        json={"username": "admin", "password": TEST_ADMIN_PASSWORD}
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

def test_security_headers_present():
    client, path = make_client()
    try:
        response = client.get("/api/creators")

        assert response.status_code == 200
        assert response.headers["X-Content-Type-Options"] == "nosniff"
        assert response.headers["X-Frame-Options"] == "DENY"
        assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"

        assert response.headers["Permissions-Policy"].startswith("camera=()")
        assert response.headers["Cross-Origin-Embedder-Policy"] == "require-corp"

        csp = response.headers["Content-Security-Policy"]
        assert "default-src 'self'" in csp
        assert "form-action 'self'" in csp
        assert "object-src 'none'" in csp
        assert "frame-ancestors 'none'" in csp
    finally:
        path.unlink(missing_ok=True)


def test_security_headers_present_on_error_response():
    client, path = make_client()
    try:
        response = client.post(
            "/api/creators",
            json={"name": "Unauthorized", "platform": "Lab", "followers": 100}
        )

        assert response.status_code == 401
        assert response.headers["X-Content-Type-Options"] == "nosniff"
        assert response.headers["X-Frame-Options"] == "DENY"
        assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
        assert "default-src 'self'" in response.headers["Content-Security-Policy"]
    finally:
        path.unlink(missing_ok=True)


def add_user(path, username):
    """Create a test user with a random password; returns the password."""
    import secrets
    from werkzeug.security import generate_password_hash
    from backend.database import get_connection
    password = secrets.token_urlsafe(16)
    connection = get_connection(str(path))
    connection.execute(
        "INSERT INTO users (username, password_hash) VALUES (?, ?)",
        (username, generate_password_hash(password)),
    )
    connection.commit()
    connection.close()
    return password


def test_other_user_cannot_modify_creator_bola():
    client, path = make_client()
    try:
        assert login(client).status_code == 200
        created = client.post(
            "/api/creators",
            json={"name": "Owned by admin", "platform": "Lab", "followers": 10}
        )
        assert created.status_code == 201
        creator_id = created.get_json()["id"]
        client.post("/api/logout")

        bob_password = add_user(path, "bob")
        assert client.post(
            "/api/login", json={"username": "bob", "password": bob_password}
        ).status_code == 200

        update = client.put(
            f"/api/creators/{creator_id}",
            json={"name": "Changed by bob", "platform": "Lab", "followers": 1}
        )
        assert update.status_code == 403

        delete = client.delete(f"/api/creators/{creator_id}")
        assert delete.status_code == 403

        still_there = client.get(f"/api/creators/{creator_id}")
        assert still_there.status_code == 200
        assert still_there.get_json()["name"] == "Owned by admin"
    finally:
        path.unlink(missing_ok=True)


def test_owner_can_still_modify_own_creator():
    client, path = make_client()
    try:
        bob_password = add_user(path, "bob")
        assert client.post(
            "/api/login", json={"username": "bob", "password": bob_password}
        ).status_code == 200

        created = client.post(
            "/api/creators",
            json={"name": "Bob creator", "platform": "Lab", "followers": 5}
        )
        assert created.status_code == 201
        creator_id = created.get_json()["id"]

        updated = client.put(
            f"/api/creators/{creator_id}",
            json={"name": "Bob creator", "platform": "Lab", "followers": 6}
        )
        assert updated.status_code == 200
        assert client.delete(f"/api/creators/{creator_id}").status_code == 200
    finally:
        path.unlink(missing_ok=True)


def test_api_errors_are_json_not_html():
    client, path = make_client()
    try:
        r404 = client.get("/api/creators/not-a-number")
        assert r404.status_code == 404
        assert r404.is_json and r404.get_json()["error"] == "Not found"
        r405 = client.patch("/api/creators/1")
        assert r405.status_code == 405
        assert r405.is_json
        assert "PUT" in r405.headers.get("Allow", "")
    finally:
        path.unlink(missing_ok=True)
