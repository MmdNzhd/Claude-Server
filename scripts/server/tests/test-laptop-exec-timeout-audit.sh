#!/bin/bash
# test-laptop-exec-timeout-audit.sh - Stage 7: timeout -k 5, RUN default 120, CMD_END on 124
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LE="$ROOT/scripts/server/laptop-exec.sh"
PASS=0; FAIL=0
ok() { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== laptop-exec timeout audit (Stage 7) ==="
echo ""

grep -q 'timeout -k 5 --foreground' "$LE" && ok 'uses timeout -k 5 --foreground' || bad 'uses timeout -k 5 --foreground'
grep -q 'LAPTOP_EXEC_RUN_TIMEOUT:-120' "$LE" && ok 'RUN default timeout is 120' || bad 'RUN default timeout is 120'
grep -q 'run 120s' "$LE" && ok 'usage documents run 120s' || bad 'usage documents run 120s'
grep -q 'meaning=timeout' "$LE" && ok 'CMD_END branch for exit 124 (timeout)' || bad 'CMD_END branch for exit 124'
grep -q 'exit=124' "$LE" && ok 'CMD_END logs exit=124' || bad 'CMD_END logs exit=124'
grep -q 'CMD_TIMEOUT' "$LE" && ok 'still logs CMD_TIMEOUT on 124 in _laptop_ssh' || bad 'still logs CMD_TIMEOUT'
if grep -q 'LAPTOP_EXEC_RUN_TIMEOUT:-600' "$LE"; then bad 'old RUN default 600 removed'; else ok 'old RUN default 600 removed'; fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS contracts passed."
  exit 0
fi
echo "$FAIL failed, $PASS passed."
exit 1
