#!/usr/bin/env python3
"""Fail if Flask routes in backend/app.py and .zap/openapi.yaml drift apart (Lab 13, SEC-2553)."""
import pathlib
import re
import sys

import yaml

VERBS = {"get", "post", "put", "patch", "delete"}
code = pathlib.Path("backend/app.py").read_text()
routes = {
    (m.group(1), re.sub(r"<(?:\w+:)?(\w+)>", r"{\1}", m.group(2)))
    for m in re.finditer(r'@\w+\.(get|post|put|patch|delete)\("([^"]+)"', code)
}
spec = yaml.safe_load(pathlib.Path(".zap/openapi.yaml").read_text())
documented = {(v, p) for p, ops in spec["paths"].items() for v in ops if v in VERBS}
for v, p in sorted(routes - documented):
    print(f"NOT IN SPEC: {v.upper()} {p}")
for v, p in sorted(documented - routes):
    print(f"NOT IN CODE: {v.upper()} {p}")
print(f"routes in code: {len(routes)}, operations in spec: {len(documented)}")
sys.exit(1 if routes != documented else 0)
