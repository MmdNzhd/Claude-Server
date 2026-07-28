#!/usr/bin/env bash
# test-laptop-exec.sh - static + optional live checks for laptop-exec UX
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LE="${ROOT}/laptop-exec.sh"
GUARD="${ROOT}/cursor-hooks/laptop-exec-guard.sh"
SESSION="${ROOT}/cursor-hooks/laptop-exec-session.sh"
SKILL="${ROOT}/skills/laptop-exec/SKILL.md"
FAIL=0
pass() { echo "  ok  $1"; }
fail() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "=== test-laptop-exec ==="
bash -n "$LE" && pass "bash -n laptop-exec.sh" || fail "bash -n laptop-exec.sh"
bash -n "$GUARD" && pass "bash -n guard" || fail "bash -n guard"
bash -n "$SESSION" && pass "bash -n session" || fail "bash -n session"

grep -q '_read_next' "$LE" && pass "_read_next" || fail "_read_next"
grep -q '_reject_abs_or_mount_path' "$LE" && pass "abs-path reject" || fail "abs-path reject"
grep -q 'must come BEFORE' "$LE" && pass "git -p order DIE" || fail "git -p order DIE"
grep -q '_LE_TUNNEL_WARNED' "$LE" && pass "TUNNEL rate-limit" || fail "TUNNEL rate-limit"
grep -q 'stripped CRLF' "$LE" && pass "write CRLF strip" || fail "write CRLF strip"

grep -q 'HEALTHY MOUNT' "$SESSION" && pass "session HEALTHY MOUNT" || fail "session HEALTHY MOUNT"
grep -q 'HEALTHY MOUNT' "$GUARD" && pass "guard HEALTHY MOUNT" || fail "guard HEALTHY MOUNT"
grep -q 'HARD RULE' "$SKILL" && pass "skill HARD RULE" || fail "skill HARD RULE"
grep -q 'Footguns' "$SKILL" && pass "skill Footguns" || fail "skill Footguns"
grep -q 'LAPTOP_EXEC_AUDIT_FAST' "$GUARD" && pass "guard AUDIT_FAST" || fail "guard AUDIT_FAST"

# Project hooks must stay empty
for cand in \
  "${HOME}/mounts/"*/.cursor/hooks.json \
  "${ROOT}/../../.cursor/hooks.json"; do
  [ -f "$cand" ] || continue
  if grep -q '"hooks"[[:space:]]*:[[:space:]]*{[[:space:]]*}' "$cand" 2>/dev/null \
     || grep -q '"hooks":{}' "$cand" 2>/dev/null; then
    pass "empty hooks $(basename "$(dirname "$(dirname "$cand")")")"
  fi
done

# Live DIE smokes when tunnel up (skip soft if down)
if command -v laptop-exec >/dev/null 2>&1 && laptop-exec status >/dev/null 2>&1; then
  out=$(laptop-exec read /home/smart/mounts/claude-code-server/README.md 2>&1 || true)
  echo "$out" | grep -qi 'mount path\|relative\|NEXT' && pass "live DIE abs mount" || fail "live DIE abs mount: $out"
  out=$(laptop-exec git status -p claude-code-server 2>&1 || true)
  echo "$out" | grep -qi 'BEFORE\|NEXT' && pass "live DIE git -p order" || fail "live DIE git -p order: $out"
else
  echo "  skip live DIE (tunnel down)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "Done. all passed"
  exit 0
fi
echo "Done. $FAIL failure(s)"
exit 1
