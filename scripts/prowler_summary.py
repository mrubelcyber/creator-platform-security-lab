"""Lab 12 (SEC-2552) - summarize Prowler CSV output (semicolon-separated).

One file:  totals + open failing checks by severity (de-duplicated by FINDING_UID;
           muted findings counted as MUTED, not FAIL - Prowler 5.44.0 once wrote rows twice).
Two files: compare BASELINE AFTER - fixed / still failing / new failing checks.
Usage: python3 prowler_summary.py RESULTS.csv
       python3 prowler_summary.py BASELINE.csv AFTER.csv
"""
import collections
import csv
import sys

ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "informational": 4}


def load(path):
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter=";"))
    if not rows:
        sys.exit(f"STOP: no rows in {path}")
    key = {k.upper(): k for k in rows[0]}
    for need in ("STATUS", "SEVERITY", "CHECK_ID"):
        if need not in key:
            sys.exit(f"STOP: column {need} not found in {path}")
    uid, muted = key.get("FINDING_UID"), key.get("MUTED")
    seen, unique = set(), []
    for r in rows:
        k = r[uid] if uid else tuple(r.values())
        if k in seen:
            continue
        seen.add(k)
        status = r[key["STATUS"]]
        if muted and status == "FAIL" and r[muted].strip().lower() in ("true", "1"):
            status = "MUTED"
        unique.append({"status": status, "severity": r[key["SEVERITY"]].lower(), "check": r[key["CHECK_ID"]]})
    return rows, unique


def open_fails(unique):
    return {u["check"] for u in unique if u["status"] == "FAIL"}


def summary(path):
    rows, unique = load(path)
    print(f"== rows in file: {len(rows)} | unique findings: {len(unique)} | duplicates removed: {len(rows) - len(unique)}")
    print("== totals", dict(collections.Counter(u["status"] for u in unique)))
    fails = collections.Counter((u["severity"], u["check"]) for u in unique if u["status"] == "FAIL")
    print("== open failing checks: resources  severity  check")
    for (sev, check), n in sorted(fails.items(), key=lambda x: (ORDER.get(x[0][0], 9), x[0][1])):
        print(f"{n:5}  {sev:<9} {check}")


def compare(base_path, after_path):
    b, a = open_fails(load(base_path)[1]), open_fails(load(after_path)[1])
    print(f"open failing checks - baseline: {len(b)} | after: {len(a)}")
    for title, items in (("FIXED", b - a), ("STILL FAILING", b & a), ("NEW FAILS", a - b)):
        print(f"== {title}: {len(items)}")
        for c in sorted(items):
            print("  ", c)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        summary(sys.argv[1])
    elif len(sys.argv) == 3:
        compare(sys.argv[1], sys.argv[2])
    else:
        sys.exit(__doc__)
