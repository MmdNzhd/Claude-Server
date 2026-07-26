#!/bin/bash
# test-cursor-server-reaper.sh - static safety contracts for reaper
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
R="$ROOT/scripts/server/cursor-server-reaper.sh"
PASS=0; FAIL=0
ok() { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== cursor-server-reaper contracts ==="
echo ""

[ -f "$R" ] && ok 'script exists' || bad 'script exists'
grep -q 'DRY_RUN=1' "$R" && ok 'default dry-run' || bad 'default dry-run'
grep -q -- '--apply' "$R" && ok 'has --apply' || bad 'has --apply'
grep -q 'MIN_AGE_SECONDS=3600' "$R" && ok 'min age 3600' || bad 'min age 3600'
grep -q 'estab' "$R" && ok 'checks estab clients' || bad 'checks estab clients'
grep -q 'protected_builds' "$R" && ok 'protects builds with clients' || bad 'protects builds with clients'
grep -q 'server-main.js' "$R" && ok 'targets server-main.js' || bad 'targets server-main.js'
grep -q 'would_kill' "$R" && ok 'dry-run logs would_kill' || bad 'dry-run logs would_kill'

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS contracts passed."
  exit 0
fi
echo "$FAIL failed, $PASS passed."
exit 1
