import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATABASE_PATH = BASE_DIR / "database" / "creator.db"

def get_connection(db_path=None):
    path = db_path or DATABASE_PATH
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    return connection

def init_db(db_path=None):
    path = db_path or DATABASE_PATH
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    connection = get_connection(path)
    connection.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS creators (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            platform TEXT NOT NULL,
            followers INTEGER NOT NULL DEFAULT 0 CHECK(followers >= 0),
            owner_id INTEGER REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS activity_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    """)

    # Lab 5: existing databases were created before owner_id existed.
    columns = [row["name"] for row in connection.execute("PRAGMA table_info(creators)")]
    if "owner_id" not in columns:
        connection.execute("ALTER TABLE creators ADD COLUMN owner_id INTEGER REFERENCES users(id)")

    connection.commit()
    connection.close()
    print(f"Database initialized: {path}")
