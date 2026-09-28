#!/bin/sh

set -e

echo "=========================================="
echo " Creator Platform Security Bootstrap"
echo "=========================================="

echo
echo "[1/3] Checking Gitleaks..."

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "ERROR: Gitleaks is not installed."
    echo "Install Gitleaks before continuing."
    exit 1
fi

echo "Gitleaks found: $(command -v gitleaks)"

echo
echo "[2/3] Configuring shared Git hooks..."

git config core.hooksPath .githooks

echo "Git hooks path: $(git config --get core.hooksPath)"

echo
echo "[3/3] Verifying pre-commit security hook..."

if [ ! -x .githooks/pre-commit ]; then
    echo "ERROR: .githooks/pre-commit is missing or not executable."
    exit 1
fi

echo "Pre-commit security hook is ready."

echo
echo "=========================================="
echo " SECURITY BOOTSTRAP COMPLETE"
echo "=========================================="
