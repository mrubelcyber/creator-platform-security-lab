import logging
import os
from pathlib import Path

from flask import Flask, jsonify, render_template, request, session
from werkzeug.security import check_password_hash, generate_password_hash

from backend.database import get_connection, init_db
from backend.models import creator_to_dict, validate_creator

BASE_DIR = Path(__file__).resolve().parent.parent

def create_app(test_config=None):
    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.update(
        SECRET_KEY=os.environ.get("FLASK_SECRET_KEY", "local-lab-only-change-me"),
        DATABASE=str(BASE_DIR / "database" / "creator.db"),
    )
    @app.after_request
    def add_security_headers(response):
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self'; "
            "img-src 'self' data:; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "frame-ancestors 'none'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        return response

    if test_config:
        app.config.update(test_config)

    log_dir = BASE_DIR / "logs"
    log_dir.mkdir(exist_ok=True)

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
        connection.execute(
            "INSERT INTO users (username, password_hash) VALUES (?, ?)",
            ("admin", generate_password_hash("ChangeMe123!")),
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

    connection.commit()
    connection.close()

    def db():
        return get_connection(app.config["DATABASE"])

    def log_event(event):
        connection = db()
        connection.execute("INSERT INTO activity_logs (event) VALUES (?)", (event,))
        connection.commit()
        connection.close()
        app.logger.info(event)

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
            log_event(f"Failed login user={username or 'blank'}")
            return jsonify(error="Invalid username or password"), 401

        session["user_id"] = user["id"]
        session["username"] = username
        log_event(f"Login succeeded user={username}")
        return jsonify(message="Login successful", username=username)

    @app.post("/api/logout")
    def logout():
        username = session.get("username", "unknown")
        session.clear()
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
            "INSERT INTO creators (name, platform, followers) VALUES (?, ?, ?)",
            (data["name"].strip(), data["platform"].strip(), int(data["followers"])),
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
        exists = connection.execute(
            "SELECT id FROM creators WHERE id = ?", (creator_id,)
        ).fetchone()

        if not exists:
            connection.close()
            return jsonify(error="Creator not found"), 404

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
        exists = connection.execute(
            "SELECT id FROM creators WHERE id = ?", (creator_id,)
        ).fetchone()

        if not exists:
            connection.close()
            return jsonify(error="Creator not found"), 404

        connection.execute("DELETE FROM creators WHERE id = ?", (creator_id,))
        connection.commit()
        connection.close()

        log_event(f"Creator deleted id={creator_id} by={session.get('username')}")
        return jsonify(message="Creator deleted")

    @app.get("/api/logs")
    def logs():
        if not session.get("user_id"):
            return jsonify(error="Authentication required"), 401

        connection = db()
        rows = connection.execute(
            "SELECT id, event, created_at FROM activity_logs "
            "ORDER BY id DESC LIMIT 50"
        ).fetchall()
        connection.close()
        return jsonify([dict(row) for row in rows])

    return app

if __name__ == "__main__":
    application = create_app()
    application.run(host="0.0.0.0", port=5000, debug=False)
