#!/bin/bash
# test-laptop-exec-abort-trap.sh - abort trap + meaning=aborted + background wait
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LE="$ROOT/scripts/server/laptop-exec.sh"
PASS=0; FAIL=0
ok() { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== laptop-exec abort trap contracts ==="
echo ""

grep -q '_le_on_signal' "$LE" && ok 'defines _le_on_signal' || bad 'defines _le_on_signal'
grep -q "trap '_le_on_signal' TERM INT HUP" "$LE" && ok 'traps TERM INT HUP' || bad 'traps TERM INT HUP'
grep -q 'meaning=aborted' "$LE" && ok 'CMD_END meaning=aborted' || bad 'CMD_END meaning=aborted'
grep -q '_le_kill_tree' "$LE" && ok 'has _le_kill_tree' || bad 'has _le_kill_tree'
grep -q '_LE_CMD_CHILD' "$LE" && ok 'tracks _LE_CMD_CHILD' || bad 'tracks _LE_CMD_CHILD'
# background ssh/timeout so trap can kill (ampersand on ssh line after timeout \)
grep -q '_LE_CMD_CHILD=$!' "$LE" && ok 'records background child pid' || bad 'records background child pid'
grep -q 'wait "$_LE_CMD_CHILD"' "$LE" && ok 'waits on _LE_CMD_CHILD' || bad 'waits on _LE_CMD_CHILD'
grep -n 'ssh -n .* "$@" &' "$LE" | grep -q . \
  && ok 'ssh launched in background' \
  || bad 'ssh launched in background'
grep -q '_LE_CMD_ENDED' "$LE" && ok 'guards double CMD_END' || bad 'guards double CMD_END'
grep -q 'LE_JOB_ID' "$LE" && ok 'embeds LE_JOB_ID for Windows orphan kill' || bad 'embeds LE_JOB_ID for Windows orphan kill'
grep -q '_le_remote_kill_win_job' "$LE" && ok 'has _le_remote_kill_win_job' || bad 'has _le_remote_kill_win_job'

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS contracts passed."
  exit 0
fi
echo "$FAIL failed, $PASS passed."
exit 1
