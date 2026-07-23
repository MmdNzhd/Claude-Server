#!/bin/bash
# test-cursor-auth-personal-denylist.sh - Stage 6e: export refuses personal email without --allow-personal
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$ROOT/scripts/server/cursor-auth-lib.py"
EXPORT="$ROOT/scripts/server/cursor-auth-export.sh"
PASS=0
FAIL=0
assert() {
  if "$@"; then echo "  PASS $*"; PASS=$((PASS+1)); else echo "  FAIL $*"; FAIL=$((FAIL+1)); fi
}
# Simpler assert with message
ok() { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=== cursor-auth personal email denylist (Stage 6e) ==="
echo ""

grep -q 'PERSONAL_EMAIL_DOMAIN_DENYLIST' "$LIB" && ok 'lib defines PERSONAL_EMAIL_DOMAIN_DENYLIST' || bad 'lib defines PERSONAL_EMAIL_DOMAIN_DENYLIST'
grep -q 'assert_export_email_allowed' "$LIB" && ok 'lib defines assert_export_email_allowed' || bad 'lib defines assert_export_email_allowed'
grep -q 'gmail.com' "$LIB" && ok 'lib denylists gmail.com' || bad 'lib denylists gmail.com'
grep -q 'outlook.com' "$LIB" && ok 'lib denylists outlook.com' || bad 'lib denylists outlook.com'
grep -q 'ALLOW_PERSONAL_EMAIL' "$LIB" && ok 'lib has ALLOW_PERSONAL_EMAIL flag' || bad 'lib has ALLOW_PERSONAL_EMAIL flag'
grep -q 'golden.quarantine-reason' "$LIB" && ok 'lib writes quarantine reason path' || bad 'lib writes quarantine reason path'
grep -q 'quarantined-personal' "$LIB" && ok 'lib references quarantined-personal (no restore)' || bad 'lib references quarantined-personal'
grep -q -- '--allow-personal' "$EXPORT" && ok 'export.sh documents --allow-personal' || bad 'export.sh documents --allow-personal'
grep -q 'ALLOW_PERSONAL' "$EXPORT" && ok 'export.sh wires ALLOW_PERSONAL' || bad 'export.sh wires ALLOW_PERSONAL'
grep -q 'golden.quarantine-reason' "$ROOT/scripts/server/commands/diagnose-auth.sh" && ok 'diagnose shows quarantine reason' || bad 'diagnose shows quarantine reason'
grep -q 'Do NOT restore' "$ROOT/scripts/server/commands/diagnose-auth.sh" && ok 'diagnose says Do NOT restore quarantined-personal' || bad 'diagnose says Do NOT restore'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PYTHONPATH=
python3 - "$LIB" "$TMP" <<'PY'
import importlib.util, json, sys, tempfile
from pathlib import Path

lib_path = Path(sys.argv[1])
tmp = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mod.GOLDEN_DIR = tmp / "golden"
mod.AUTH_JSON = mod.GOLDEN_DIR / "auth.json"
mod.STORAGE_JSON = mod.GOLDEN_DIR / "storage.json"
mod.STATE_KEYS_JSON = mod.GOLDEN_DIR / "state-keys.json"
mod.MACHINE_ID_TXT = mod.GOLDEN_DIR / "machine-id.txt"
mod.EXPORTED_AT = mod.GOLDEN_DIR / "exported-at"
mod.SOURCE_HOST = mod.GOLDEN_DIR / "source-host"
mod.QUARANTINE_REASON_PATH = tmp / "golden.quarantine-reason"
mod.QUARANTINE_DIR = tmp / "golden.quarantined-personal"
mod.ALLOW_PERSONAL_EMAIL = False

assert mod.is_personal_email("alice@gmail.com")
assert mod.is_personal_email("bob@outlook.com")
assert not mod.is_personal_email("dev@smartx.ir")

# Refuse write without flag
state = {
    "cursorAuth/accessToken": "tok-access",
    "cursorAuth/refreshToken": "tok-refresh",
    "cursorAuth/cachedEmail": "personal.user@gmail.com",
    "storage.serviceMachineId": "mid-1",
    "telemetry.machineId": "mid-1",
    "telemetry.macMachineId": "mid-1",
    "telemetry.devDeviceId": "mid-1",
    "telemetry.sqmId": "mid-1",
}
storage = {k: "mid-1" for k in mod.STORAGE_JSON_KEYS}
refused = False
try:
    mod.write_golden_bundle(state, storage, "test-host")
except SystemExit as exc:
    refused = True
    msg = str(exc)
    assert "REFUSE personal email" in msg or "personal_email_denylist" in msg
    assert "gmail.com" in msg
if not refused:
    raise SystemExit("expected refuse for gmail without allow_personal")
if mod.AUTH_JSON.is_file():
    raise SystemExit("auth.json must not be written on refuse")
qr = mod.read_quarantine_reason()
assert qr and qr.get("email") == "personal.user@gmail.com"
assert qr.get("reason") == "personal_email_denylist"

# Escape hatch
mod.ALLOW_PERSONAL_EMAIL = True
mod.write_golden_bundle(state, dict(storage), "test-host")
assert mod.AUTH_JSON.is_file()
auth = json.loads(mod.AUTH_JSON.read_text(encoding="utf-8"))
assert auth.get("cachedEmail") == "personal.user@gmail.com"

# Work email allowed by default
mod.ALLOW_PERSONAL_EMAIL = False
mod.GOLDEN_DIR = tmp / "golden-work"
mod.AUTH_JSON = mod.GOLDEN_DIR / "auth.json"
mod.STORAGE_JSON = mod.GOLDEN_DIR / "storage.json"
mod.STATE_KEYS_JSON = mod.GOLDEN_DIR / "state-keys.json"
mod.MACHINE_ID_TXT = mod.GOLDEN_DIR / "machine-id.txt"
mod.EXPORTED_AT = mod.GOLDEN_DIR / "exported-at"
mod.SOURCE_HOST = mod.GOLDEN_DIR / "source-host"
state2 = dict(state)
state2["cursorAuth/cachedEmail"] = "dev@smartx.ir"
mod.write_golden_bundle(state2, dict(storage), "test-host")
assert mod.AUTH_JSON.is_file()
print("RUNTIME_OK")
PY
if [ "${PIPESTATUS[0]}" = "0" ] || [ $? -eq 0 ]; then
  # python prints RUNTIME_OK
  :
fi
# Re-run capturing
if out="$(python3 - "$LIB" "$TMP" <<'PY'
import importlib.util, json, sys
from pathlib import Path
lib_path = Path(sys.argv[1]); tmp = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod.GOLDEN_DIR = tmp / "golden2"; mod.AUTH_JSON = mod.GOLDEN_DIR / "auth.json"
mod.STORAGE_JSON = mod.GOLDEN_DIR / "storage.json"; mod.STATE_KEYS_JSON = mod.GOLDEN_DIR / "state-keys.json"
mod.MACHINE_ID_TXT = mod.GOLDEN_DIR / "machine-id.txt"; mod.EXPORTED_AT = mod.GOLDEN_DIR / "exported-at"
mod.SOURCE_HOST = mod.GOLDEN_DIR / "source-host"
mod.QUARANTINE_REASON_PATH = tmp / "q2"; mod.QUARANTINE_DIR = tmp / "qp2"
mod.ALLOW_PERSONAL_EMAIL = False
state = {"cursorAuth/accessToken":"a","cursorAuth/refreshToken":"r","cursorAuth/cachedEmail":"x@gmail.com",
 "storage.serviceMachineId":"m","telemetry.machineId":"m","telemetry.macMachineId":"m",
 "telemetry.devDeviceId":"m","telemetry.sqmId":"m"}
storage = {k:"m" for k in mod.STORAGE_JSON_KEYS}
try:
    mod.write_golden_bundle(state, storage, "h")
    print("UNEXPECTED_OK"); raise SystemExit(2)
except SystemExit as e:
    if "personal" in str(e).lower() or "REFUSE" in str(e):
        print("REFUSE_OK")
    else:
        print("BAD_EXIT", e); raise
PY
)"; then
  echo "$out" | grep -q REFUSE_OK && ok 'runtime: export refuses denylisted gmail without flag' || bad "runtime refuse: $out"
else
  bad 'runtime python refuse probe failed'
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS contracts passed."
  exit 0
fi
echo "$FAIL failed, $PASS passed."
exit 1
