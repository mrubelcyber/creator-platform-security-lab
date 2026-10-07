import logging
import os
from pathlib import Path

from flask import Flask, g, jsonify, render_template, request, session
from werkzeug.security import check_password_hash, generate_password_hash

from backend.database import get_connection, init_db
from backend.models import creator_to_dict, validate_creator
from backend.security_log import (
    configure_security_log,
    log_unrecorded_client_error,
    security_event,
    start_request,
)

BASE_DIR = Path(__file__).resolve().parent.parent

def create_app(test_config=None):
    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.update(
        SECRET_KEY=os.environ.get("FLASK_SECRET_KEY", "local-lab-only-change-me"),
        DATABASE=str(BASE_DIR / "database" / "creator.db"),
    )
    @app.before_request
    def assign_request_id():
        start_request()

    @app.after_request
    def add_security_headers(response):
        log_unrecorded_client_error(response)
        response.headers["X-Request-ID"] = g.get("request_id", "")
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self'; "
            "img-src 'self' data:; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "form-action 'self'; "
            "frame-ancestors 'none'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
        return response

    if test_config:
        app.config.update(test_config)

    log_dir = Path(os.environ.get("LOG_DIR", BASE_DIR / "logs"))
    log_dir.mkdir(parents=True, exist_ok=True)
    configure_security_log(log_dir, app.testing)

    if not app.testing:
        handler = logging.FileHandler(log_dir / "application.log")
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        app.logger.addHandler(handler)
        app.logger.setLevel(logging.INFO)

    init_db(app.config["DATABASE"])

    connection = get_connection(app.config["DATABASE"])
    user = connection.execute(
        "SELECT id FROM users WHERE username = ?", ("admin",)
    ).fetchone()

    if not user:
        initial_password = (
            app.config.get("ADMIN_INITIAL_PASSWORD")
            or os.environ.get("ADMIN_INITIAL_PASSWORD")
        )
        if initial_password:
            connection.execute(
                "INSERT INTO users (username, password_hash) VALUES (?, ?)",
                ("admin", generate_password_hash(initial_password)),
            )
        else:
            app.logger.warning(
                "No admin account created: set ADMIN_INITIAL_PASSWORD "
                "or run scripts/create_user.py admin"
            )

    count = connection.execute(
        "SELECT COUNT(*) AS total FROM creators"
    ).fetchone()["total"]

    if count == 0:
        connection.executemany(
            "INSERT INTO creators (name, platform, followers) VALUES (?, ?, ?)",
            [
                ("Aisha", "Instagram", 125000),
                ("David", "YouTube", 85000),
                ("Maria", "TikTok", 210000),
            ],
        )

    # Lab 5: creators without an owner belong to the seeded admin account.
    connection.execute(
        "UPDATE creators SET owner_id = (SELECT id FROM users WHERE username = ?) "
        "WHERE owner_id IS NULL",
        ("admin",),
    )

    connection.commit()
    connection.close()

    def db():
        return get_connection(app.config["DATABASE"])

    def log_event(event):
        # CWE-117: never let user input start a new line in the activity log
        event = event.replace("\r", "\\r").replace("\n", "\\n")
        connection = db()
        connection.execute("INSERT INTO activity_logs (event) VALUES (?)", (event,))
        connection.commit()
        connection.close()
        app.logger.info(event)

    def owned_creator_or_error(connection, creator_id, action):
        """Object-level authorization: only the owner may change a creator."""
        row = connection.execute(
            "SELECT id, owner_id FROM creators WHERE id = ?", (creator_id,)
        ).fetchone()
        if not row:
            return None, (jsonify(error="Creator not found"), 404)
        if row["owner_id"] != session.get("user_id"):
            security_event("authz.denied", "denied", status=403,
                           action=action, creator_id=creator_id)
            log_event(
                f"Authorization denied action={action} creator_id={creator_id} "
                f"user={session.get('username')}"
            )
            return None, (jsonify(error="You are not allowed to modify this creator"), 403)
        return row, None

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/health")
    def health():
        return jsonify(application="Creator Platform", status="healthy")

    @app.post("/api/login")
    def login():
        data = request.get_json(silent=True) or {}
        username = str(data.get("username", "")).strip()
        password = str(data.get("password", ""))

        connection = db()
        user = connection.execute(
            "SELECT * FROM users WHERE username = ?", (username,)
        ).fetchone()
        connection.close()

        if not user or not check_password_hash(user["password_hash"], password):
            security_event("auth.login", "failure", status=401,
                           target_user=username or "blank",
                           reason="unknown_user" if not user else "bad_password")
            log_event(f"Failed login user={username or 'blank'}")
            return jsonify(error="Invalid username or password"), 401

        session["user_id"] = user["id"]
        session["username"] = username
        security_event("auth.login", "success", user=username)
        log_event(f"Login succeeded user={username}")
        return jsonify(message="Login successful", username=username)

    @app.post("/api/logout")
    def logout():
        username = session.get("username", "unknown")
        session.clear()
        security_event("auth.logout", "success", user=username)
        log_event(f"Logout user={username}")
        return jsonify(message="Logged out")

    @app.get("/api/session")
    def session_status():
        return jsonify(
            authenticated=bool(session.get("user_id")),
            username=session.get("username"),
        )

    @app.get("/api/creators")
    def creators():
        connection = db()
        rows = connection.execute(
            "SELECT * FROM creators ORDER BY id"
        ).fetchall()
        connection.close()
        return jsonify([creator_to_dict(row) for row in rows])

    @app.get("/api/creators/<int:creator_id>")
    def creator(creator_id):
        connection = db()
        row = connection.execute(
            "SELECT * FROM creators WHERE id = ?", (creator_id,)
        ).fetchone()
        connection.close()

        if not row:
            return jsonify(error="Creator not found"), 404
        return jsonify(creator_to_dict(row))

    @app.post("/api/creators")
    def create_creator():
        if not session.get("user_id"):
            return jsonify(error="Authentication required"), 401

        data = request.get_json(silent=True)
        error = validate_creator(data)
        if error:
            return jsonify(error=error), 400

        connection = db()
        cursor = connection.execute(
            "INSERT INTO creators (name, platform, followers, owner_id) VALUES (?, ?, ?, ?)",
            (data["name"].strip(), data["platform"].strip(), int(data["followers"]),
             session["user_id"]),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM creators WHERE id = ?", (cursor.lastrowid,)
        ).fetchone()
        connection.close()

        log_event(f"Creator created id={row['id']} by={session.get('username')}")
        return jsonify(creator_to_dict(row)), 201

    @app.put("/api/creators/<int:creator_id>")
    def update_creator(creator_id):
        if not session.get("user_id"):
            return jsonify(error="Authentication required"), 401

        data = request.get_json(silent=True)
        error = validate_creator(data)
        if error:
            return jsonify(error=error), 400

        connection = db()
        _, denied = owned_creator_or_error(connection, creator_id, "update")
        if denied:
            connection.close()
            return denied

        connection.execute(
            "UPDATE creators SET name=?, platform=?, followers=? WHERE id=?",
            (data["name"].strip(), data["platform"].strip(),
             int(data["followers"]), creator_id),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM creators WHERE id = ?", (creator_id,)
        ).fetchone()
        connection.close()

        log_event(f"Creator updated id={creator_id} by={session.get('username')}")
        return jsonify(creator_to_dict(row))

    @app.delete("/api/creators/<int:creator_id>")
    def delete_creator(creator_id):
        if not session.get("user_id"):
            return jsonify(error="Authentication required"), 401

        connection = db()
        _, denied = owned_creator_or_error(connection, creator_id, "delete")
        if denied:
            connection.close()
            return denied

        connection.execute("DELETE FROM creators WHERE id = ?", (creator_id,))
        connection.commit()
        connection.close()

        log_event(f"Creator deleted id={creator_id} by={session.get('username')}")
        return jsonify(message="Creator deleted")

    @app.get("/api/logs")
    def logs():
        if not session.get("user_id"):
            return jsonify(error="Authentication required"), 401

        security_event("audit.logs_read", "success")
        connection = db()
        rows = connection.execute(
            "SELECT id, event, created_at FROM activity_logs "
            "ORDER BY id DESC LIMIT 50"
        ).fetchall()
        connection.close()
        return jsonify([dict(row) for row in rows])


    # Lab 13 (SEC-2553): API errors as JSON, not Flask HTML pages (ZAP 100001)
    @app.errorhandler(404)
    def not_found(_error):
        return jsonify(error="Not found"), 404

    @app.errorhandler(405)
    def method_not_allowed(error):
        allowed = ", ".join(getattr(error, "valid_methods", None) or [])
        return jsonify(error="Method not allowed"), 405, {"Allow": allowed}

    @app.errorhandler(500)
    def internal_error(_error):
        return jsonify(error="Internal server error"), 500

    return app

if __name__ == "__main__":
    application = create_app()
    application.run(host="0.0.0.0", port=5000, debug=False)
