"""Creator Platform detection rules: read logs/security.log and raise alerts.

Usage:
    python scripts/detect.py [path/to/security.log]
Exit code 0 = no HIGH/CRITICAL alerts, 1 = at least one HIGH/CRITICAL alert,
2 = the log file could not be read (setup error, not an attack).
"""
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta

WINDOW = timedelta(seconds=60)
SENSITIVE_PATHS = ("/.env", "/.git", "/admin", "/wp-admin", "/wp-login.php",
                   "/phpmyadmin", "/server-status", "/config")
SEVERITY_ORDER = {"LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}


def load_events(path):
    events = []
    with open(path) as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
                event["_time"] = datetime.fromisoformat(event["timestamp"])
                events.append(event)
            except (ValueError, KeyError):
                print(f"WARNING: skipped unreadable line {number}", file=sys.stderr)
    return sorted(events, key=lambda e: e["_time"])


def alert(rule, severity, title, events, **details):
    return {
        "rule": rule,
        "severity": severity,
        "title": title,
        "src_ip": events[0].get("src_ip"),
        "first_seen": events[0]["timestamp"],
        "last_seen": events[-1]["timestamp"],
        "count": len(events),
        "request_ids": [e.get("request_id") for e in events][:10],
        **details,
    }


def in_window(events, minimum):
    """Return the first group of >= minimum events that fall inside WINDOW."""
    for start in range(len(events)):
        group = [e for e in events[start:] if e["_time"] - events[start]["_time"] <= WINDOW]
        if len(group) >= minimum:
            return group
    return None


def detect(events):
    alerts = []
    by_ip = defaultdict(list)
    for event in events:
        by_ip[event.get("src_ip")].append(event)

    for ip, ip_events in by_ip.items():
        failures = [e for e in ip_events if e["event"] == "auth.login" and e["outcome"] == "failure"]

        # DET-001 Brute force: 5+ failed logins from one IP within 60 seconds
        burst = in_window(failures, 5)
        if burst:
            alerts.append(alert("DET-001", "HIGH", "Brute-force login attempt", burst,
                                target_users=sorted({e.get("target_user") for e in burst})))

            # DET-002 Success after brute force: possible account compromise
            last_failure = burst[-1]["_time"]
            for e in ip_events:
                if (e["event"] == "auth.login" and e["outcome"] == "success"
                        and timedelta(0) <= e["_time"] - last_failure <= timedelta(minutes=10)):
                    alerts.append(alert("DET-002", "CRITICAL",
                                        "Successful login right after brute force", burst + [e],
                                        compromised_user=e.get("user")))
                    break

        # DET-003 Account enumeration: 3+ different unknown usernames within 60 seconds
        unknown = [e for e in failures if e.get("reason") == "unknown_user"]
        group = in_window(unknown, 3)
        if group and len({e.get("target_user") for e in group}) >= 3:
            alerts.append(alert("DET-003", "MEDIUM", "Username enumeration / password spraying", group,
                                target_users=sorted({e.get("target_user") for e in group})))

        # DET-004 BOLA attempts: a user denied access to other users' records
        denied = [e for e in ip_events if e["event"] == "authz.denied"]
        if denied:
            severity = "HIGH" if len(denied) >= 2 else "MEDIUM"
            alerts.append(alert("DET-004", severity, "Access to another user's records denied (BOLA attempt)",
                                denied, users=sorted({str(e.get("user")) for e in denied}),
                                creator_ids=sorted({e.get("creator_id") for e in denied})))

        # DET-005 Reconnaissance: probing sensitive paths or unusual methods
        probes = [e for e in ip_events if e["event"] == "http.client_error" and (
            e.get("path", "").lower().startswith(SENSITIVE_PATHS) or e.get("status") == 405)]
        if probes:
            alerts.append(alert("DET-005", "MEDIUM", "Reconnaissance: sensitive path probes / unusual methods",
                                probes, paths=sorted({f'{e.get("method")} {e.get("path")}' for e in probes})))

        # DET-006 Unauthenticated access to the audit log endpoint
        log_probe = [e for e in ip_events if e.get("path") == "/api/logs" and e.get("status") == 401]
        if log_probe:
            alerts.append(alert("DET-006", "MEDIUM", "Unauthenticated attempt to read audit logs", log_probe))

    # DET-007 Log injection: line breaks or control characters in any logged value
    injected = [e for e in events if any(
        isinstance(v, str) and any(c in v for c in "\r\n\x1b") for k, v in e.items() if k != "_time")]
    if injected:
        alerts.append(alert("DET-007", "HIGH", "Log injection attempt (control characters in input)", injected))

    return sorted(alerts, key=lambda a: (-SEVERITY_ORDER[a["severity"]], a["rule"]))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "logs/security.log"
    try:
        events = load_events(path)
    except OSError as error:
        print(f"ERROR: cannot read {path}: {error.strerror}", file=sys.stderr)
        return 2
    alerts = detect(events)
    print(f"Analyzed {len(events)} events from {path}: {len(alerts)} alert(s)")
    for a in alerts:
        print(f'[{a["severity"]:8}] {a["rule"]} {a["title"]} | src_ip={a["src_ip"]} '
              f'count={a["count"]} first={a["first_seen"]}')
    with open(path.replace("security.log", "alerts.json") if path.endswith("security.log")
              else "alerts.json", "w") as out:
        json.dump(alerts, out, indent=2, default=str)
    return 1 if any(SEVERITY_ORDER[a["severity"]] >= 3 for a in alerts) else 0


if __name__ == "__main__":
    sys.exit(main())
