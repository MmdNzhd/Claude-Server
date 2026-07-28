#!/usr/bin/env bash
# test-tunnel-port-heal-hard.sh — HT1 unit fixtures for TUNNEL_PORT heal (no live amir)
#
# Maps to hard-test cases:
#   HT1.1 empty PORT + live formula → TUNNEL_PORT_HEALED (marker must exist)
#   HT1.2 legacy PORT=20000+uid + formula live → TUNNEL_PORT_LEGACY_HEALED / LEGACY_HEALED
#         (FAIL until GREEN adds rewrite when conf has deprecated 20000+UID)
#   HT1.3 correct formula PORT → no rewrite (heal must not clobber good ports)
#   HT1.4 dead legacy → no false heal to dead port
#         (live TCP probe; documented skip here — run under HT1.5–1.6)
#   HT1.7 substring false-positive: grepping HEALED must not match LEGACY_HEALED
#         ambiguously; markers must be distinct exact strings
#
# Prefer strong static RED. Live fixture (temp HOME + CONNECT_CONF + mock tcp)
# is hard without extracting _load_global — covered by HT1.5–1.6 skip note.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LE="$ROOT/laptop-exec.sh"
FAIL=0
pass() { echo "  ok  $1"; }
fail() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "=== test-tunnel-port-heal-hard (HT1 static) ==="
echo "LE=$LE"

if [ ! -f "$LE" ]; then
  fail "laptop-exec.sh missing at $LE"
  echo "Done. $FAIL failure(s)"
  exit 1
fi

bash -n "$LE" && pass "bash -n laptop-exec.sh" || fail "bash -n laptop-exec.sh"

# Extract _load_global body for scoped asserts (through next top-level function).
_load_body=$(sed -n '/^_load_global()/,/^_load_project()/p' "$LE")
if [ -z "$_load_body" ]; then
  fail "HT1: could not extract _load_global body"
  _load_body=""
fi

# --- HT1.1: empty PORT + live formula → HEALED marker exists ---
# Current code: if [ -z "$TUNNEL_PORT" ]; then ... TUNNEL_PORT_HEALED ...
if echo "$_load_body" | grep -qF 'TUNNEL_PORT_HEALED'; then
  pass "HT1.1 TUNNEL_PORT_HEALED marker present (empty-PORT heal path)"
else
  fail "HT1.1 TUNNEL_PORT_HEALED marker missing (empty PORT + live formula heal)"
fi

if echo "$_load_body" | grep -qE '\[ -z "\$TUNNEL_PORT" \]'; then
  pass "HT1.1 empty-PORT gate ([ -z \"\$TUNNEL_PORT\" ]) present"
else
  fail "HT1.1 empty-PORT gate missing in _load_global"
fi

# --- HT1.2: legacy PORT=20000+uid → LEGACY_HEALED (RED until GREEN) ---
# Current code only heals when TUNNEL_PORT is empty. When conf stores the
# deprecated 20000+UID value (e.g. Smart 21002), it must rewrite to the live
# formula port and emit TUNNEL_PORT_LEGACY_HEALED or LEGACY_HEALED.
_legacy_marker=0
if echo "$_load_body" | grep -qF 'TUNNEL_PORT_LEGACY_HEALED'; then
  _legacy_marker=1
elif echo "$_load_body" | grep -qF 'LEGACY_HEALED'; then
  _legacy_marker=1
fi
if [ "$_legacy_marker" -eq 1 ]; then
  pass "HT1.2 LEGACY_HEALED / TUNNEL_PORT_LEGACY_HEALED marker present"
else
  fail "HT1.2 LEGACY_HEALED marker missing (legacy PORT=20000+uid rewrite path)"
fi

# Heal must not ONLY check empty PORT — require an explicit comparison when
# TUNNEL_PORT equals the deprecated 20000+uid value (_deprecated).
# Do NOT match warn strings like "deprecated_would_be=${_deprecated}".
_legacy_path=0
if echo "$_load_body" | grep -qE \
  '\[ "\$TUNNEL_PORT" (=|-eq) "\$_deprecated" \]|\[ "\$_deprecated" (=|-eq) "\$TUNNEL_PORT" \]'; then
  _legacy_path=1
fi
# Alternate GREEN shapes: explicit eq against $((20000 + _uid)) / 20000+_uid
if echo "$_load_body" | grep -qE \
  '\[ "\$TUNNEL_PORT" (=|-eq) "\$_?(deprecated|legacy)(_port)?" \]|TUNNEL_PORT.*(legacy|deprecated).*(-eq|=)'; then
  # Still require an equality test token, not warn-line substring
  if echo "$_load_body" | grep -qE '\[ "\$TUNNEL_PORT"'; then
    if echo "$_load_body" | grep -qE '(-eq|=) "\$(_deprecated|_legacy|\(\(20000)'; then
      _legacy_path=1
    fi
  fi
fi
if [ "$_legacy_path" -eq 1 ]; then
  pass "HT1.2 legacy set-PORT rewrite path (PORT equals 20000+uid)"
else
  fail "HT1.2 no legacy set-PORT rewrite (only empty-PORT heal; need PORT==20000+uid path)"
fi

# --- HT1.3: correct formula PORT → no rewrite ---
# Static contract: when TUNNEL_PORT is already the formula fallback, heal must
# not rewrite. Document: GREEN must gate rewrite on empty OR equals-deprecated,
# never on "any non-formula" without live probe. Assert empty-heal block does
# not run when PORT is set (structure: rewrite inside -z OR explicit legacy eq).
if echo "$_load_body" | grep -qF 'TUNNEL_PORT_HEALED'; then
  # HEALED audit must sit inside the empty-PORT branch (before the closing fi
  # of -z), not as an unconditional rewrite of any PORT.
  _hz=$(echo "$_load_body" | grep -n '\[ -z "\$TUNNEL_PORT" \]' | head -1 | cut -d: -f1)
  _hh=$(echo "$_load_body" | grep -nF 'TUNNEL_PORT_HEALED' | head -1 | cut -d: -f1)
  if [ -n "$_hz" ] && [ -n "$_hh" ] && [ "$_hh" -gt "$_hz" ]; then
    pass "HT1.3 TUNNEL_PORT_HEALED scoped after empty-PORT gate (correct PORT not auto-healed by empty path)"
  else
    fail "HT1.3 TUNNEL_PORT_HEALED not clearly scoped after empty-PORT gate"
  fi
else
  fail "HT1.3 cannot verify HEALED scope (marker missing)"
fi

# --- HT1.4: dead legacy → no false heal (document / skip live) ---
# Live: CONNECT_CONF with TUNNEL_PORT=$legacy, formula port NOT listening →
# must NOT rewrite to dead formula. Requires mock tcp; skip in this unit file.
echo "  skip HT1.4 live dead-legacy false-heal (needs TCP mock; see HT1.5–1.6)"

# --- HT1.7: substring false-positive note for logs ---
# Markers must be distinct: grepping bare HEALED would also match
# TUNNEL_PORT_LEGACY_HEALED. Tests and log scrapers must use exact tokens.
if echo "$_load_body" | grep -qF 'TUNNEL_PORT_HEALED'; then
  if echo "$_load_body" | grep -qE '_le_audit_log[[:space:]]+INFO[[:space:]]+TUNNEL_PORT_HEALED'; then
    pass "HT1.7 exact audit token TUNNEL_PORT_HEALED (avoid bare HEALED grep FP)"
  else
    pass "HT1.7 TUNNEL_PORT_HEALED string present (prefer full _le_audit_log INFO token)"
  fi
else
  fail "HT1.7 cannot assert exact HEALED token (missing)"
fi
# Document: when GREEN adds LEGACY_HEALED, scrapers must grep -F
# TUNNEL_PORT_LEGACY_HEALED or LEGACY_HEALED, never substring 'HEALED' alone.
echo "  note HT1.7: log scrapers must grep exact TUNNEL_PORT_HEALED / LEGACY_HEALED (not bare HEALED)"

if [ "$FAIL" -eq 0 ]; then
  echo "Done. all passed"
  exit 0
fi
echo "Done. $FAIL failure(s)"
exit 1
