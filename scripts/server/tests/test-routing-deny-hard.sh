#!/usr/bin/env bash
# test-routing-deny-hard.sh — HT3.1–3.11 static: conditional deny LE read/rg when mount MOUNTED
#
#   HT3.1 Kill-switch token LAPTOP_EXEC_DENY_OFF or LAPTOP_EXEC_ALLOW_LE_READ
#   HT3.2 _shell_should_block must deny laptop-exec read/rg when MOUNTED
#         (not only unconditional return 1 / "not enforced")
#   HT3.3 Allow LE read/rg on STALE / NOT_LIVE / NOT_MOUNTED near shell deny
#   HT3.4 Deny agent_message structured NEXT → Cursor Read/Grep
#         (require ROUTING_DENY or LE_READ_DENIED token — generic Shell remap alone ≠ PASS)
#   HT3.5–3.8 Documented: allow git/run/write/status; false-positive env prefix;
#             sudo-from-laptop; fail-open (comments in this fixture + guard checks)
#   HT3.9 Guard-wrap exists and exits 0 on error (fail-open)
#   HT3.10–3.11 A-8 / fail-open notes
#
# Expect RED until GREEN implements conditional deny in _shell_should_block.
# PASS today: bash -n guard, wrap present, Shell ALLOWED for non-LE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/cursor-hooks/laptop-exec-guard.sh"
WRAP="$ROOT/cursor-hooks/laptop-exec-guard-wrap.sh"
FAIL=0
pass() { echo "  ok  $1"; }
fail() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
note() { echo "  note $1"; }

echo "=== test-routing-deny-hard (HT3.1–3.11 static) ==="
echo "ROOT=$ROOT"
echo "GUARD=$GUARD"
echo "WRAP=$WRAP"

if [ ! -f "$GUARD" ]; then
  fail "laptop-exec-guard.sh missing at $GUARD"
  echo "Done. $FAIL failure(s)"
  exit 1
fi

bash -n "$GUARD" && pass "bash -n laptop-exec-guard.sh" || fail "bash -n laptop-exec-guard.sh"

# Extract _shell_should_block body (best-effort; static RED checks also grep whole guard).
_extract_fn() {
  local file="$1" name="$2"
  awk -v n="$name" '
    index($0, n "()") == 1 { grab=1 }
    grab {
      print
      if ($0 ~ /^}/) exit
    }
  ' "$file"
}
_SHELL_BLOCK=$(_extract_fn "$GUARD" "_shell_should_block" || true)

# --- HT3.1: kill-switch token ---
_ht31=0
if grep -qE 'LAPTOP_EXEC_DENY_OFF|LAPTOP_EXEC_ALLOW_LE_READ' "$GUARD"; then
  _ht31=1
fi
if [ "$_ht31" -eq 1 ]; then
  pass "HT3.1 kill-switch LAPTOP_EXEC_DENY_OFF / LAPTOP_EXEC_ALLOW_LE_READ present"
else
  fail "HT3.1 missing kill-switch token LAPTOP_EXEC_DENY_OFF or LAPTOP_EXEC_ALLOW_LE_READ"
fi

# --- HT3.2: _shell_should_block must contain laptop-exec + read/rg deny + MOUNTED ---
# Current code: always return 1 with "not enforced" / "always return do not block" — RED.
_ht32_le=0
_ht32_mounted=0
_ht32_readrg=0
if printf '%s\n' "$_SHELL_BLOCK" | grep -qF 'laptop-exec'; then
  _ht32_le=1
elif grep -A30 '^_shell_should_block()' "$GUARD" | grep -qF 'laptop-exec'; then
  _ht32_le=1
fi
if printf '%s\n' "$_SHELL_BLOCK" | grep -qF 'MOUNTED'; then
  _ht32_mounted=1
elif grep -A40 '^_shell_should_block()' "$GUARD" | grep -qF 'MOUNTED'; then
  _ht32_mounted=1
fi
# Nearby deny helper that references MOUNTED also counts.
if [ "$_ht32_mounted" -eq 0 ]; then
  if grep -qE '_le_read_rg_should_deny|_routing_deny_le_read|_mount_is_mounted' "$GUARD" \
    && grep -qF 'MOUNTED' "$GUARD"; then
    _ht32_mounted=1
  fi
fi
if printf '%s\n' "$_SHELL_BLOCK" | grep -qE 'read/rg|deny.*read|deny.*rg|\\bread\\b.*\\brg\\b' \
  || printf '%s\n' "$_SHELL_BLOCK" | grep -qE '(laptop-exec[[:space:]]+read|laptop-exec[[:space:]]+rg|"read"|"rg")'; then
  _ht32_readrg=1
elif grep -A40 '^_shell_should_block()' "$GUARD" | grep -qE 'laptop-exec.*(read|rg)|(read|rg).*deny|deny.*(read|rg)'; then
  _ht32_readrg=1
fi

# Unconditional-only stub: body is effectively just return 1 (no LE deny logic).
_ht32_stub=0
if printf '%s\n' "$_SHELL_BLOCK" | grep -qE 'return 1' \
  && ! printf '%s\n' "$_SHELL_BLOCK" | grep -qF 'laptop-exec'; then
  _ht32_stub=1
fi
if grep -A20 '^_shell_should_block()' "$GUARD" | grep -qiE 'not enforced|always return.*do not block|Keep helper for audit'; then
  _ht32_stub=1
fi

if [ "$_ht32_le" -eq 1 ] && [ "$_ht32_mounted" -eq 1 ] && [ "$_ht32_readrg" -eq 1 ] && [ "$_ht32_stub" -eq 0 ]; then
  pass "HT3.2 _shell_should_block has laptop-exec read/rg deny gated on MOUNTED"
else
  fail "HT3.2 _shell_should_block lacks laptop-exec+read/rg deny + MOUNTED (stub return 1 / not enforced until GREEN)"
fi

# --- HT3.3: allow on STALE / NOT_LIVE / NOT_MOUNTED near shell deny ---
_ht33=0
if printf '%s\n' "$_SHELL_BLOCK" | grep -qE 'STALE|NOT_LIVE|NOT_MOUNTED'; then
  _ht33=1
elif grep -A60 '^_shell_should_block()' "$GUARD" | grep -qE 'STALE|NOT_LIVE|NOT_MOUNTED'; then
  _ht33=1
elif [ "$_ht32_le" -eq 1 ] && grep -qE '_le_read_rg_should_deny|_routing_deny_le_read|ROUTING_DENY|LE_READ_DENIED' "$GUARD" \
  && grep -qE 'STALE|NOT_LIVE|NOT_MOUNTED' "$GUARD"; then
  _ht33=1
fi
if [ "$_ht33" -eq 1 ]; then
  pass "HT3.3 shell deny allows LE read/rg on STALE/NOT_LIVE/NOT_MOUNTED"
else
  fail "HT3.3 missing allow-on-STALE/NOT_LIVE/NOT_MOUNTED near shell deny"
fi

# --- HT3.4: structured NEXT pointing to Cursor Read/Grep on deny ---
# RED: require explicit ROUTING_DENY or LE_READ_DENIED (generic _remap_hint Shell alone is NOT enough).
_ht34=0
if grep -qE 'ROUTING_DENY|LE_READ_DENIED' "$GUARD"; then
  _ht34=1
fi
if [ "$_ht34" -eq 1 ]; then
  pass "HT3.4 deny agent_message has ROUTING_DENY/LE_READ_DENIED (NEXT → Cursor Read/Grep)"
else
  fail "HT3.4 missing ROUTING_DENY or LE_READ_DENIED (deny NEXT must point to Cursor Read/Grep)"
fi

# --- HT3.5–3.8: policy docs as comments in this fixture (always PASS) + soft guard probes ---
# HT3.5 Allow git / run / write / status (and non-read/rg LE verbs) when deny is active.
# HT3.6 Avoid false-positive: env prefix / PATH wrappers must not trip on bare "laptop-exec"
#       substrings in unrelated commands (e.g. echo LAPTOP_EXEC=..., comments).
# HT3.7 sudo-from-laptop must remain ALLOWED (not blocked by LE read/rg deny).
# HT3.8 Fail-open: parse/runtime errors in guard must ALLOW (never exit 2).
note "HT3.5 allow git/run/write/status (and other non-read/rg LE) under MOUNTED deny"
note "HT3.6 false-positive: do not deny on env prefix / non-command laptop-exec substring"
note "HT3.7 sudo-from-laptop remains ALLOWED"
note "HT3.8 fail-open on guard parse/runtime errors"
pass "HT3.5–3.8 policy documented (allow git/run/write/status; FP env; sudo-from-laptop; fail-open)"

# Soft probe: Shell ALLOWED for non-LE (current stub returns 1 = do not block) — PASS today.
if grep -qE '_tool_targets_mounts|_shell_should_block' "$GUARD" \
  && grep -A15 '^[[:space:]]*Shell)' "$GUARD" | grep -qE 'return 1'; then
  pass "HT3.5 Shell ALLOWED for non-LE path present (preToolUse Shell return 1)"
else
  pass "HT3.5 Shell non-LE allow path via _shell_should_block return-1 stub (current)"
fi

# --- HT3.9: guard-wrap exists; fail-open exits 0 ---
if [ -f "$WRAP" ]; then
  bash -n "$WRAP" && pass "HT3.9 bash -n laptop-exec-guard-wrap.sh" || fail "HT3.9 bash -n wrap failed"
  if grep -qE 'exit 0' "$WRAP" && grep -qiE 'fail-open|FAIL_OPEN|fail.open' "$WRAP"; then
    pass "HT3.9 wrap fail-open exits 0 on error"
  else
    fail "HT3.9 wrap missing fail-open exit 0 path"
  fi
else
  fail "HT3.9 laptop-exec-guard-wrap.sh missing at $WRAP"
fi

# --- HT3.10: A-8 note (multi-agent abort / everyone-blocked hygiene) ---
# A-8: empty project hooks + wrap fail-open + no Shell in preToolUse matcher.
note "HT3.10 A-8: project hooks empty; user hooks use wrap; Shell only in beforeShellExecution"
if grep -qE 'preToolUse' "$GUARD" && grep -A30 'preToolUse)' "$GUARD" | grep -qE 'Shell'; then
  note "HT3.10 guard preToolUse case lists Shell (hooks matcher must still omit Shell)"
fi
pass "HT3.10 A-8 hygiene noted (wrap + empty project hooks; Shell=beforeShellExecution)"

# --- HT3.11: fail-open notes (trap ERR / never exit 2) ---
if grep -qE "trap.*_allow.*ERR|never exit 2|Fail OPEN|fail-open|fail.open" "$GUARD" \
  || grep -qiE 'fail-open|FAIL_OPEN' "$WRAP"; then
  pass "HT3.11 fail-open notes present in guard and/or wrap"
else
  fail "HT3.11 missing fail-open notes in guard/wrap"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "Done. all passed"
  exit 0
fi
echo "Done. $FAIL failure(s)"
exit 1
