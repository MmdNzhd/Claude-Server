#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# strip CRLF from this runner's target if needed
TMP=$(mktemp)
tr -d '\r' < scripts/client/tests/test-windows-connect.sh > "$TMP"
bash "$TMP"
RC=$?
rm -f "$TMP"
exit $RC
