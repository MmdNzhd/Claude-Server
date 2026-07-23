#!/bin/bash
# test-cursor-auth-golden-perms.sh - Stage 8
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$ROOT/scripts/server/cursor-auth-lib.py"
EXP="$ROOT/scripts/server/cursor-auth-export.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL $1"; FAIL=$((FAIL+1)); }
echo ""; echo "=== cursor-auth golden perms (Stage 8) ==="; echo ""
grep -q 'def apply_golden_permissions' "$LIB" && ok 'lib defines apply_golden_permissions' || bad 'lib defines apply_golden_permissions'
grep -q '0o750' "$LIB" && ok 'lib sets dirs 0750' || bad 'lib sets dirs 0750'
grep -q 'mode=0o640' "$LIB" && ok 'lib writes shared mode=0o640' || bad 'lib writes shared mode=0o640'
grep -q 'mode=0o644' "$LIB" && ok 'lib writes exported-at mode=0o644' || bad 'lib writes exported-at mode=0o644'
grep -q 'apply_golden_permissions()' "$LIB" && ok 'write_golden_bundle calls apply' || bad 'write_golden_bundle calls apply'
grep -q 'apply_golden_permissions' "$EXP" && ok 'export.sh calls apply' || bad 'export.sh calls apply'
grep -q 'apply_golden_permissions' "$ROOT/scripts/server/cursor-auth-refresh.sh" && ok 'refresh calls apply' || bad 'refresh calls apply'
if grep -q 'os.chmod(GOLDEN_DIR, 0o700)' "$LIB"; then bad 'no bare GOLDEN_DIR 0700'; else ok 'no bare GOLDEN_DIR 0700'; fi
out=$(python3 - "$LIB" <<'PY'
import importlib.util, os, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("cal", Path(sys.argv[1]))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
posix_tmp = Path("/tmp") / ("golden-perms-" + str(os.getpid()))
posix_tmp.mkdir(parents=True, exist_ok=True)
mod.GOLDEN_DIR = posix_tmp / "golden"
mod.AUTH_JSON = mod.GOLDEN_DIR / "auth.json"
mod.STORAGE_JSON = mod.GOLDEN_DIR / "storage.json"
mod.STATE_KEYS_JSON = mod.GOLDEN_DIR / "state-keys.json"
mod.MACHINE_ID_TXT = mod.GOLDEN_DIR / "machine-id.txt"
mod.EXPORTED_AT = mod.GOLDEN_DIR / "exported-at"
mod.SOURCE_HOST = mod.GOLDEN_DIR / "source-host"
mod.ALLOW_PERSONAL_EMAIL = True
called = {"n": 0}
_orig = mod.apply_golden_permissions
def _wrap():
    called["n"] += 1
    return _orig()
mod.apply_golden_permissions = _wrap
state = {"cursorAuth/accessToken":"a","cursorAuth/refreshToken":"r","cursorAuth/cachedEmail":"dev@smartx.ir",
 "storage.serviceMachineId":"m","telemetry.machineId":"m","telemetry.macMachineId":"m",
 "telemetry.devDeviceId":"m","telemetry.sqmId":"m"}
mod.write_golden_bundle(state, {k:"m" for k in mod.STORAGE_JSON_KEYS}, "h")
assert called["n"] >= 1, "apply_golden_permissions not called"
assert oct(mod.GOLDEN_DIR.stat().st_mode & 0o777) == "0o750", oct(mod.GOLDEN_DIR.stat().st_mode & 0o777)
assert oct(mod.AUTH_JSON.stat().st_mode & 0o777) == "0o640"
assert oct(mod.EXPORTED_AT.stat().st_mode & 0o777) == "0o644"
assert oct(mod.STORAGE_JSON.stat().st_mode & 0o777) == "0o600"
print("RUNTIME_OK")
PY
)
echo "$out" | grep -q RUNTIME_OK && ok 'runtime modes 0750/0640/0644/0600' || bad "runtime modes ($out)"
echo ""
if [ "$FAIL" -eq 0 ]; then echo "All $PASS contracts passed."; exit 0; fi
echo "$FAIL failed, $PASS passed."; exit 1
