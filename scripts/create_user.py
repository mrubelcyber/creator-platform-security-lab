"""Create a local Creator Platform user without putting a password in code or Git.

Usage:
    python scripts/create_user.py <username>
The password is typed at a hidden prompt.
"""
import getpass
import os
import sys

from werkzeug.security import generate_password_hash

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from backend.database import DATABASE_PATH, get_connection, init_db  # noqa: E402


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--reset"):
        print("Usage: python scripts/create_user.py <username> [--reset]")
        return 1

    username = sys.argv[1].strip()
    reset = len(sys.argv) == 3
    db_path = os.environ.get("CREATOR_DB", str(DATABASE_PATH))
    password = getpass.getpass(f"Password for {username}: ")
    if len(password) < 12:
        print("Password must be at least 12 characters.")
        return 1

    init_db(db_path)
    connection = get_connection(db_path)
    exists = connection.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
    if reset:
        if not exists:
            print(f"User {username} does not exist.")
            connection.close()
            return 1
        connection.execute(
            "UPDATE users SET password_hash = ? WHERE username = ?",
            (generate_password_hash(password), username),
        )
        connection.commit()
        connection.close()
        print(f"Password changed for {username}")
        return 0
    if exists:
        print(f"User {username} already exists.")
        connection.close()
        return 1

    connection.execute(
        "INSERT INTO users (username, password_hash) VALUES (?, ?)",
        (username, generate_password_hash(password)),
    )
    connection.commit()
    connection.close()
    print(f"Created user {username} in {db_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
