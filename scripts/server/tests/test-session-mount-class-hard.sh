#!/usr/bin/env bash
# test-session-mount-class-hard.sh — HT2.1–2.9 static: mount class + DIE NEXT
#
#   HT2.1 Session emits MOUNT_CLASS=MOUNTED or class=/mount_class=MOUNTED
#         (not only mount=LIVE / HEALTHY MOUNT LIVE)
#   HT2.2 Session handles STALE as mount class (word STALE; not TUNNEL_PORT_LEGACY_STALE)
#         — fail if session is binary LIVE/NOT_LIVE only
#   HT2.3 Session emits NOT_LIVE or NOT_MOUNTED as class (PASS if NOT_LIVE already)
#   HT2.4 ACTIVE_MISMATCH exact token when ACTIVE_MOUNT != workspace pid
#   HT2.5–2.8 DIE NEXT: _rg_next, _read_next, git BEFORE, invent-verbs, abs-mount
#   HT2.9 Session must NOT use mountpoint -q (prefer /proc/mounts)
#
# Also PASS if LE already has _sshfs_state returning MOUNTED/STALE.
# Expect RED until GREEN adds explicit mount-class tokens in session.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SESSION="$ROOT/cursor-hooks/laptop-exec-session.sh"
LE="$ROOT/laptop-exec.sh"
FAIL=0
pass() { echo "  ok  $1"; }
fail() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "=== test-session-mount-class-hard (HT2.1–2.9 static) ==="
echo "ROOT=$ROOT"
echo "SESSION=$SESSION"
echo "LE=$LE"

if [ ! -f "$SESSION" ]; then
  fail "laptop-exec-session.sh missing at $SESSION"
  echo "Done. $FAIL failure(s)"
  exit 1
fi
if [ ! -f "$LE" ]; then
  fail "laptop-exec.sh missing at $LE"
  echo "Done. $FAIL failure(s)"
  exit 1
fi

bash -n "$SESSION" && pass "bash -n laptop-exec-session.sh" || fail "bash -n laptop-exec-session.sh"
bash -n "$LE" && pass "bash -n laptop-exec.sh" || fail "bash -n laptop-exec.sh"

# --- HT2.1: explicit mount class token (MOUNTED) — RED until GREEN ---
# Accept MOUNT_CLASS=MOUNTED / class=MOUNTED / mount_class=MOUNTED in session
# paste or audit. mount=LIVE / HEALTHY MOUNT LIVE alone is NOT enough.
_ht21=0
if grep -qE 'MOUNT_CLASS=MOUNTED' "$SESSION"; then
  _ht21=1
elif grep -qE 'mount_class=MOUNTED' "$SESSION"; then
  _ht21=1
elif grep -qE '(^|[^[:alnum:]_])class=MOUNTED([^[:alnum:]_]|$)' "$SESSION"; then
  _ht21=1
fi
if [ "$_ht21" -eq 1 ]; then
  pass "HT2.1 session emits MOUNT_CLASS=MOUNTED or class=/mount_class=MOUNTED"
else
  fail "HT2.1 missing MOUNT_CLASS=MOUNTED / class=MOUNTED / mount_class=MOUNTED (mount=LIVE / HEALTHY MOUNT LIVE not enough)"
fi

# --- HT2.2: STALE as mount class in session (not TUNNEL_PORT_LEGACY_STALE) ---
# Strip LEGACY_STALE noise then require word STALE as a class token.
_sess_no_legacy=$(grep -vF 'TUNNEL_PORT_LEGACY_STALE' "$SESSION" || true)
_ht22=0
if printf '%s\n' "$_sess_no_legacy" | grep -qwE 'STALE'; then
  _ht22=1
fi
# Class-shaped tokens also count
if printf '%s\n' "$_sess_no_legacy" | grep -qE 'MOUNT_CLASS=STALE|class=STALE|mount_class=STALE'; then
  _ht22=1
fi
if [ "$_ht22" -eq 1 ]; then
  pass "HT2.2 session emits STALE as mount class"
else
  fail "HT2.2 session missing STALE mount class (binary LIVE/NOT_LIVE only; need ls/I/O STALE path)"
fi

# --- HT2.3: NOT_LIVE or NOT_MOUNTED as class (PASS if NOT_LIVE already) ---
_ht23=0
if grep -qE 'NOT_LIVE|NOT_MOUNTED' "$SESSION"; then
  _ht23=1
fi
if [ "$_ht23" -eq 1 ]; then
  pass "HT2.3 session emits NOT_LIVE or NOT_MOUNTED as class"
else
  fail "HT2.3 session missing NOT_LIVE / NOT_MOUNTED class token"
fi

# --- HT2.4: ACTIVE_MISMATCH exact audit/paste token — RED until GREEN ---
if grep -qF 'ACTIVE_MISMATCH' "$SESSION"; then
  pass "HT2.4 ACTIVE_MISMATCH exact token present in session"
else
  fail "HT2.4 ACTIVE_MISMATCH missing (ACTIVE_MOUNT != workspace pid needs exact token)"
fi

# --- HT2.5: _rg_next emits NEXT: ---
if grep -qF '_rg_next' "$LE" && grep -A5 '^_rg_next()' "$LE" | grep -qF 'NEXT:'; then
  pass "HT2.5 _rg_next contains NEXT:"
elif grep -n '_die "rg:' "$LE" | grep -q 'NEXT:'; then
  pass "HT2.5 rg DIE lines include NEXT:"
else
  fail "HT2.5 _rg_next / rg DIE missing NEXT:"
fi

# --- HT2.6: _read_next emits NEXT: ---
if grep -qF '_read_next' "$LE" && grep -A5 '^_read_next()' "$LE" | grep -qF 'NEXT:'; then
  pass "HT2.6 _read_next contains NEXT:"
elif grep -nE '_die "read:' "$LE" | grep -qE 'NEXT:|_read_next'; then
  pass "HT2.6 read DIE includes NEXT: / _read_next"
else
  fail "HT2.6 _read_next / read DIE missing NEXT:"
fi

# --- HT2.7: git -p BEFORE subcommand DIE includes NEXT: ---
if grep -n 'git: -p/--project must come BEFORE' "$LE" | grep -q 'NEXT:'; then
  pass "HT2.7 git BEFORE DIE includes NEXT:"
else
  fail "HT2.7 git BEFORE DIE missing NEXT:"
fi

# --- HT2.8: invent-verbs DIE + abs-mount DIE each contain NEXT: ---
_ht28=0
if grep -n 'unknown command' "$LE" | grep -q 'NEXT:'; then
  pass "HT2.8 invent-verbs DIE includes NEXT:"
  _ht28=1
else
  fail "HT2.8 invent-verbs (unknown command) DIE missing NEXT:"
fi
if grep -nE 'Linux mount path not valid|absolute path not supported' "$LE" | grep -q 'NEXT:'; then
  pass "HT2.8 abs-mount DIE includes NEXT:"
  _ht28=1
else
  fail "HT2.8 abs-mount DIE missing NEXT:"
fi
# silence unused if both fail
: "$_ht28"

# --- Bonus PASS: LE _sshfs_state returns MOUNTED/STALE ---
_sshfs_ok=0
if grep -qE '^_sshfs_state' "$LE"; then
  if grep -A40 '^_sshfs_state_uncached()' "$LE" | grep -qF 'echo "STALE"' \
    && grep -A40 '^_sshfs_state_uncached()' "$LE" | grep -qF 'echo "MOUNTED"'; then
    _sshfs_ok=1
  elif grep -A80 '^_sshfs_state()' "$LE" | grep -qE 'echo "STALE"|echo "MOUNTED"'; then
    # fallback: body inline in _sshfs_state
    if grep -A80 '^_sshfs_state()' "$LE" | grep -qF 'STALE' \
      && grep -A80 '^_sshfs_state()' "$LE" | grep -qF 'MOUNTED'; then
      _sshfs_ok=1
    fi
  fi
fi
if [ "$_sshfs_ok" -eq 1 ]; then
  pass "LE _sshfs_state returns MOUNTED/STALE (bonus PASS)"
else
  fail "LE _sshfs_state missing MOUNTED/STALE return values"
fi

# --- HT2.9: session must NOT use mountpoint -q; prefer /proc/mounts ---
_mp_call=0
if grep -vE '^[[:space:]]*#' "$SESSION" | grep -qE 'mountpoint[[:space:]]+-q'; then
  _mp_call=1
fi
if [ "$_mp_call" -eq 0 ]; then
  pass "HT2.9 session has no uncommented mountpoint -q"
else
  fail "HT2.9 session invokes mountpoint -q (must prefer /proc/mounts)"
fi
if grep -qF '/proc/mounts' "$SESSION"; then
  pass "HT2.9 session prefers /proc/mounts"
else
  fail "HT2.9 session missing /proc/mounts"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "Done. all passed"
  exit 0
fi
echo "Done. $FAIL failure(s)"
exit 1
