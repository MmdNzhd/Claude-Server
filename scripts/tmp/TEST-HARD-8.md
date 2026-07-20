# TEST-HARD-8 — Session ID + Silent 30m Update Matrix

**Date:** 2026-07-20  
**Agent:** T8 (laptop-exec only, `-p claude-code-server`)  
**Method:** `laptop-exec rg` + `laptop-exec read` source snippets; throttle dry-run (local, no SSH)  
**Deploy:** none

---

## Summary

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Win bat sets `CLAUDE_CONNECT_RUN_ID` before BOOTSTRAP | **PASS** |
| 2 | Mac `connect.sh` exports RUN_ID before `connect-update.sh` | **PASS** |
| 3 | `init_connect_log` reuses `CLAUDE_CONNECT_RUN_ID` (no date-$$ overwrite) | **PASS** |
| 4 | `Invoke-ConnectSilentUpdateCheck`: 1800 throttle, Quiet, UPDATE_SILENT, exit2 no relaunch | **FAIL** (Mac PASS / Win FAIL) |
| 5 | `begin_connect_recovery` / `Begin-ConnectRecovery`: silent ONLY on auto | **PASS** |
| 6 | Manual path does not call silent update | **PASS** |
| 7 | `connect-update` Quiet / `CLAUDE_CONNECT_UPDATE_QUIET` suppresses user output | **PARTIAL** (Mac PASS / Win FAIL) |
| 8 | `TUNNEL_DROP` structured fields on auto drop | **PASS** |

## **OVERALL: FAIL**

Primary gaps: Windows `Invoke-ConnectSilentUpdateCheck` is **missing** from `connect-ui.ps1` (referenced only from `connect.ps1` via `Get-Command`, so auto-recovery silent update is a no-op). Windows `connect-update.ps1` `-Quiet` switch checks `$script:Quiet` but never assigns it; env `CLAUDE_CONNECT_UPDATE_QUIET` is Mac-only.

---

## 1. Win bat sets CLAUDE_CONNECT_RUN_ID before BOOTSTRAP

**Result: PASS**

```bat
if not defined CLAUDE_CONNECT_RUN_ID (
  for /f %%I in ('powershell ... [guid]::NewGuid()...') do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
REM Log double-click immediately (before update)
powershell ... BOOTSTRAP: connect.bat start ... $env:CLAUDE_CONNECT_RUN_ID ...
if exist "%HERE%connect-update.ps1" (
    powershell ... connect-update.ps1 ...
```

**Evidence:** `scripts/client/windows/connect.bat` lines 11–19 set RUN_ID, log BOOTSTRAP at 19, call `connect-update.ps1` at 23.

---

## 2. Mac connect.sh exports RUN_ID before connect-update.sh

**Result: PASS**

```bash
if [ -z "${CLAUDE_CONNECT_RUN_ID:-}" ]; then
    CLAUDE_CONNECT_RUN_ID="$(python3 -c 'import uuid; ...')"
    ...
fi
export CLAUDE_CONNECT_RUN_ID
printf '... BOOTSTRAP: connect.sh start ...' >> "$_bootstrap_log_file"
_update_script="$(cd "$(dirname "$0")" && pwd)/connect-update.sh"
if [ -f "$_update_script" ]; then
    bash "$_update_script"
```

**Evidence:** `scripts/client/mac/connect.sh` lines 9–27 — export at 15, BOOTSTRAP at 20–22, update at 25–27.

---

## 3. init_connect_log reuses CLAUDE_CONNECT_RUN_ID

**Result: PASS**

**Mac/bash (`init_connect_log` in connect-ui.sh):**

```bash
if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ] && [ "${#CLAUDE_CONNECT_RUN_ID}" -ge 8 ]; then
    CONNECT_SESSION_ID="$CLAUDE_CONNECT_RUN_ID"
elif [ -n "${CONNECT_SESSION_ID:-}" ] && [ "${#CONNECT_SESSION_ID}" -ge 8 ]; then
    CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
else
    CONNECT_SESSION_ID="$(connect_session_id)"   # uuid fallback only if unset
    CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
fi
export CLAUDE_CONNECT_RUN_ID
```

**Windows (`Get-ConnectSessionId` + `Initialize-ConnectLog` in connect-ui.ps1):**

```powershell
} elseif ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
    $script:ConnectSessionId = $env:CLAUDE_CONNECT_RUN_ID.Trim()
} else {
    $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
}
$env:CLAUDE_CONNECT_RUN_ID = $script:ConnectSessionId
# Initialize-ConnectLog calls: $null = Get-ConnectSessionId
```

**Evidence:** Existing RUN_ID preserved; `date+$$` / new guid only when env unset or too short.

---

## 4. Invoke-ConnectSilentUpdateCheck (1800 / Quiet / UPDATE_SILENT / exit2 no relaunch)

**Result: FAIL** (Mac **PASS**, Windows **FAIL**)

### Mac — PASS (`invoke_connect_silent_update_check` in connect-ui.sh)

| Sub-check | Evidence | Result |
|-----------|----------|--------|
| 1800s throttle | `if [ "$last_check" -gt 0 ] && [ "$age_sec" -lt 1800 ]` → `UPDATE_SILENT skip reason=throttle` | PASS |
| Quiet | `CLAUDE_CONNECT_UPDATE_QUIET=1 bash "$update_sh"` | PASS |
| UPDATE_SILENT logs | `connect_log "UPDATE_SILENT age_min=... result=... exit=... pending_restart=..."` | PASS |
| exit2 pending_restart, no relaunch | `case 2) result='applied'; pending=1` — logs only, no `exec`/`call` | PASS |

### Windows — FAIL

| Sub-check | Evidence | Result |
|-----------|----------|--------|
| Function exists | `rg Invoke-ConnectSilentUpdateCheck scripts/client/connect-ui.ps1` → **no matches** | **FAIL** |
| Called from recovery | `Begin-ConnectRecovery` calls `Invoke-ConnectSilentUpdateCheck` only when `$Trigger -eq 'auto'` | logic OK, **dead code** |
| 1800 / UPDATE_SILENT | Not present in connect-ui.ps1 (verified via PowerShell `-match` → False) | **FAIL** |

**Note:** `test-connect-pipeline.ps1` asserts `$ui -match 'Invoke-ConnectSilentUpdateCheck'` — would fail against current tree.

---

## 5. Recovery: silent ONLY on auto

**Result: PASS**

**Windows (`Begin-ConnectRecovery` in connect.ps1):**

```powershell
if ($Trigger -eq 'auto') {
    if (Get-Command Invoke-ConnectSilentUpdateCheck -ErrorAction SilentlyContinue) {
        Invoke-ConnectSilentUpdateCheck
    }
}
```

**Mac (`begin_connect_recovery` in git-mode.sh):**

```bash
if [ "$trigger" = "auto" ] && declare -F invoke_connect_silent_update_check >/dev/null 2>&1; then
    invoke_connect_silent_update_check || true
fi
```

---

## 6. Manual path does not call silent update

**Result: PASS**

Manual reconnect uses `-Trigger 'manual'` / `begin_connect_recovery manual` — silent block is inside `auto` branch only.

**Evidence:**
- `connect.ps1`: `Begin-ConnectRecovery -Trigger 'manual'` (line ~1706) vs `-Trigger 'auto'` (line ~1752)
- `connect.sh`: `begin_connect_recovery manual` (line ~1066) vs `begin_connect_recovery auto` (line ~1083)

---

## 7. connect-update Quiet suppresses user output

**Result: PARTIAL** (Mac **PASS**, Windows **FAIL**)

### Mac — PASS (`connect-update.sh`)

```bash
UPDATE_QUIET=0
[ "${CLAUDE_CONNECT_UPDATE_QUIET:-0}" = "1" ] && UPDATE_QUIET=1
_update_msg() {
    [ "$UPDATE_QUIET" -eq 1 ] && return 0
    printf "$@"
}
```

Silent recovery sets `CLAUDE_CONNECT_UPDATE_QUIET=1` before invoking update script.

### Windows — FAIL (`connect-update.ps1`)

```powershell
param([switch]$Quiet)
function Write-UpdateMsg {
    if (-not $script:Quiet) { Write-Host ... }   # uses $script:Quiet
}
```

- `$script:Quiet` is **never assigned** from `$Quiet` or `$env:CLAUDE_CONNECT_UPDATE_QUIET`
- Env var `CLAUDE_CONNECT_UPDATE_QUIET` is **not read** on Windows
- `-Quiet` switch therefore does not suppress output today

---

## 8. TUNNEL_DROP structured fields on auto drop

**Result: PASS**

**Mac auto drop (`connect.sh` → `log_tunnel_drop` in git-mode.sh):**

```bash
log_tunnel_drop auto_reconnect "${ACTIVE_PROJECT_ID:-?}" false ...
# log_tunnel_drop emits:
# TUNNEL_DROP reason=... soft_fail=... sync_fail=... tcp_open=... tunnel_up=...
# tunnel_sync_ok=... project=... editor_opened=... editor_seen=... gen=...
# [drop_cause=...] [bg_pid=...] port=...
```

**Windows auto drop (`connect.ps1` → `Write-TunnelDropLog` in git-mode.ps1):**

```powershell
Write-TunnelDropLog -Reason 'auto_reconnect' -TunnelSyncOk:$tunnelSyncOk -ProjectId $go.Id `
    -EditorOpened:$editorOpened -EditorSeen:$script:EditorSeenOpen -RecoveryGen $script:RecoveryGeneration -Pid $bgPid
# Emits: TUNNEL_DROP reason=... soft_fail=... sync_fail=... tcp_open=... tunnel_up=...
# tunnel_sync_ok=... project=... editor_opened=... editor_seen=... gen=... port=... bg_pid=... drop_cause=...
```

Both platforms log structured key=value fields on automatic tunnel drop (not manual R with key).

---

## Optional: Throttle dry-run (no SSH)

Local Python simulation of `age_sec < 1800` gate:

| Case | age | Expected | Actual |
|------|-----|----------|--------|
| 15m ago | 900s | skip | skip PASS |
| 29m ago | 1740s | skip | skip PASS |
| 30m ago | 1800s | run | run PASS |
| 31m ago | 1860s | run | run PASS |
| never (0) | — | run | run PASS |

**Throttle boundary logic: PASS**

---

## Recommended fixes (informational — not applied)

1. Port `invoke_connect_silent_update_check` from `connect-ui.sh` → `connect-ui.ps1` as `Invoke-ConnectSilentUpdateCheck` (1800 throttle, UPDATE_SILENT logs, `-Quiet`, exit2 no relaunch).
2. In `connect-update.ps1`: `$script:Quiet = $Quiet.IsPresent -or ($env:CLAUDE_CONNECT_UPDATE_QUIET -eq '1')`.
3. Re-run `test-connect-pipeline.ps1` silent-update asserts after (1)+(2).

---

*Generated by Agent T8 — read-only audit, no deploy.*
