"""Structured security logging (one JSON object per line) for the Creator Platform."""
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

from flask import g, has_request_context, request, session

LOGGER = logging.getLogger("creator.security")
LOG_FILE_NAME = "security.log"


def configure_security_log(log_dir, testing=False):
    """Write security events to <log_dir>/security.log (not in tests)."""
    LOGGER.setLevel(logging.INFO)
    if testing:
        return
    path = os.path.abspath(Path(log_dir) / LOG_FILE_NAME)
    if not any(getattr(h, "baseFilename", None) == path for h in LOGGER.handlers):
        handler = logging.FileHandler(path)
        handler.setFormatter(logging.Formatter("%(message)s"))
        LOGGER.addHandler(handler)


def start_request():
    """Give every request an ID so its events can be followed in the logs."""
    g.request_id = uuid.uuid4().hex[:16]
    g.security_logged = False


def security_event(event, outcome, user=None, **fields):
    """Log one security event as JSON. json.dumps escapes line breaks,
    so user input can never start a new (fake) log line - CWE-117."""
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "event": event,
        "outcome": outcome,
    }
    if has_request_context():
        record.update({
            "src_ip": request.remote_addr,
            "method": request.method,
            "path": request.path,
            "user": user if user is not None else session.get("username"),
            "user_agent": request.headers.get("User-Agent", ""),
            "request_id": g.get("request_id"),
        })
        g.security_logged = True
    record.update(fields)
    level = logging.INFO if outcome == "success" else logging.WARNING
    LOGGER.log(level, json.dumps(record, ensure_ascii=True, default=str))


def log_unrecorded_client_error(response):
    """Record blocked/failed requests (4xx) that no route logged itself."""
    if 400 <= response.status_code < 500 and not g.get("security_logged"):
        security_event("http.client_error", "denied", status=response.status_code)
