#!/usr/bin/env bash
# Lab 12 (SEC-2552) - pinned Prowler scan, run from AWS CloudShell.
# Installs Prowler if missing (/tmp is wiped when CloudShell restarts), scans one Region against
# CIS 5.0 + AWS FSBP, summarizes failures (de-duplicated, muted counted separately), hashes the evidence.
# Usage:  bash prowler-scan.sh [output-name]                       e.g. prowler-baseline, prowler-after
#         MUTELIST=lab12-mutelist.yaml bash prowler-scan.sh prowler-muted
set -euo pipefail
PROWLER_VERSION="${PROWLER_VERSION:-5.44.0}"
REGION="${AWS_REGION:-us-east-1}"
VENV=/tmp/prowler-venv
OUT="$HOME/lab12-evidence/prowler"
NAME="${1:-prowler-baseline}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "$VENV/bin/prowler" ]; then
  if python3 -c 'import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)'; then
    PY=python3
  else
    sudo dnf install -y -q python3.11 python3.11-pip
    PY=python3.11
  fi
  echo "Installing Prowler $PROWLER_VERSION with $("$PY" --version) - 3-10 min, silent until done..."
  rm -rf "$VENV"
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "prowler==$PROWLER_VERSION"
fi
"$VENV/bin/prowler" --version

LIST="$("$VENV/bin/prowler" aws --list-compliance)"
FW=()
for f in cis_5.0_aws aws_foundational_security_best_practices_aws; do
  if grep -qw -- "$f" <<<"$LIST"; then FW+=("$f"); fi
done
[ "${#FW[@]}" -eq 2 ] || { echo "STOP: expected 2 frameworks, found: ${FW[*]:-none}"; exit 1; }
echo "frameworks: ${FW[*]}"

EXTRA=()
if [ -n "${MUTELIST:-}" ]; then
  [ -f "$MUTELIST" ] || { echo "STOP: mutelist file $MUTELIST not found"; exit 1; }
  EXTRA=(--mutelist-file "$MUTELIST")
  echo "mutelist: $MUTELIST"
fi

mkdir -p "$OUT"
rc=0
"$VENV/bin/prowler" aws --region "$REGION" --compliance "${FW[@]}" \
  --output-formats csv json-ocsf html --output-directory "$OUT" --output-filename "$NAME" \
  "${EXTRA[@]}" || rc=$?
echo "prowler exit code: $rc   (3 = scan completed and found FAIL results - expected)"
[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || { echo "STOP: scan error"; exit "$rc"; }

python3 "$HERE/prowler_summary.py" "$OUT/$NAME.csv"
(cd "$OUT" && find . -type f -name "${NAME}*" -exec sha256sum {} + >"MANIFEST-$NAME.sha256" \
  && echo "== evidence manifest" && cat "MANIFEST-$NAME.sha256")
