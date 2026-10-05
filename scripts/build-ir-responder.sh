#!/usr/bin/env bash
# Build lambda/ir-responder/build/responder.zip reproducibly (fixed mtime + no extra attrs)
# and print the hash for terraform/incident-response (var.lambda_code_sha256).
set -euo pipefail
cd "$(dirname "$0")/../lambda/ir-responder"
mkdir -p build && rm -f build/responder.zip
TZ=UTC touch -t 202601010000 responder.py
TZ=UTC zip -q -X build/responder.zip responder.py
echo "lambda_code_sha256 = \"$(openssl dgst -sha256 -binary build/responder.zip | base64)\""
