"""Unit tests for the detection rules in scripts/detect.py."""
import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "detect", Path(__file__).resolve().parent.parent / "scripts" / "detect.py")
detect = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(detect)

START = datetime(2026, 10, 3, 12, 0, 0, tzinfo=timezone.utc)


def event(seconds, name, outcome="denied", ip="10.0.0.5", **fields):
    when = START + timedelta(seconds=seconds)
    record = {"timestamp": when.isoformat(timespec="milliseconds"), "event": name,
              "outcome": outcome, "src_ip": ip, "request_id": f"r{seconds}", **fields}
    record["_time"] = when
    return record


def rules(alerts):
    return {a["rule"] for a in alerts}


def failed_login(seconds, user="admin", reason="bad_password", ip="10.0.0.5"):
    return event(seconds, "auth.login", "failure", ip=ip, status=401,
                 target_user=user, reason=reason)


def test_brute_force_and_success_after_it():
    events = [failed_login(i) for i in range(5)]
    events.append(event(30, "auth.login", "success", user="admin"))
    alerts = detect.detect(events)
    assert {"DET-001", "DET-002"} <= rules(alerts)
    assert next(a for a in alerts if a["rule"] == "DET-002")["severity"] == "CRITICAL"


def test_slow_failures_are_not_brute_force():
    events = [failed_login(i * 120) for i in range(5)]   # one every 2 minutes
    assert "DET-001" not in rules(detect.detect(events))


def test_username_enumeration():
    events = [failed_login(i, user=name, reason="unknown_user")
              for i, name in enumerate(["root", "test", "oracle"])]
    assert "DET-003" in rules(detect.detect(events))


def test_bola_attempts():
    events = [event(0, "authz.denied", user="bob", status=403, action="update", creator_id=4),
              event(1, "authz.denied", user="bob", status=403, action="delete", creator_id=4)]
    alert = next(a for a in detect.detect(events) if a["rule"] == "DET-004")
    assert alert["severity"] == "HIGH"
    assert alert["users"] == ["bob"]


def test_recon_and_audit_log_probe():
    events = [event(0, "http.client_error", method="GET", path="/.env", status=404),
              event(1, "http.client_error", method="TRACE", path="/", status=405),
              event(2, "http.client_error", method="GET", path="/api/logs", status=401)]
    assert {"DET-005", "DET-006"} <= rules(detect.detect(events))


def test_log_injection():
    events = [failed_login(0, user="guest\nINFO Login succeeded user=admin", reason="unknown_user")]
    assert "DET-007" in rules(detect.detect(events))


def test_normal_activity_raises_no_alerts():
    events = [event(0, "auth.login", "success", user="admin"),
              event(5, "audit.logs_read", "success", user="admin"),
              event(9, "auth.logout", "success", user="admin")]
    assert detect.detect(events) == []


def test_main_exit_code(tmp_path, monkeypatch):
    log = tmp_path / "security.log"
    lines = [dict(failed_login(i)) for i in range(5)]
    for line in lines:
        line.pop("_time")
    log.write_text("\n".join(json.dumps(line) for line in lines) + "\n")
    monkeypatch.setattr("sys.argv", ["detect.py", str(log)])
    assert detect.main() == 1
    assert json.loads((tmp_path / "alerts.json").read_text())[0]["rule"] == "DET-001"


def test_missing_log_file_is_a_setup_error(tmp_path, monkeypatch):
    monkeypatch.setattr("sys.argv", ["detect.py", str(tmp_path / "missing.log")])
    assert detect.main() == 2
