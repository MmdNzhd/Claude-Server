# FIX-AGENT-SILENT-UPDATE (Agent4)

Date: 2026-07-20
Spec: `scripts/tmp/SPEC-SESSION-LOG-UPDATE-20260720.md`
Deploy: NO

## Summary

Silent client update check on **auto** tunnel recovery only. Throttled to once per 30 minutes. All activity logged with session id via `Write-ConnectLog` / `connect_log`; no user-facing update messages on this path.

## Changes

### Windows

| File | Change |
|------|--------|
| `scripts/client/connect-ui.ps1` | Added `Invoke-ConnectSilentUpdateCheck` |
| `scripts/client/windows/connect.ps1` | Call helper from `Begin-ConnectRecovery` when `$Trigger -eq 'auto'` |
| `scripts/client/windows/connect-update.ps1` | Already had `-Quiet` + `Write-UpdateMsg` gate (no change) |

**State file:** `%USERPROFILE%\.config\claude-connect\.last-update-check` (unix epoch ASCII)

**Flow:**
1. Read last-check epoch; if age < 1800s -> log `UPDATE_SILENT skip reason=throttle age_min=N` DEBUG; return (no stamp)
2. Run `connect-update.ps1 -ScriptDir $scriptDir -Quiet`
3. Map exit: 0=ok INFO, 1=fail ERROR, 2=applied WARN pending_restart=1 (no mid-session relaunch)
4. Stamp last-check in `finally` (success, fail, unreachable, exception)
5. Manual `R` uses `Begin-ConnectRecovery -Trigger manual` -> **no update check**

### Mac

| File | Change |
|------|--------|
| `scripts/client/connect-ui.sh` | Added `invoke_connect_silent_update_check` |
| `scripts/client/git-mode.sh` | Call helper from `begin_connect_recovery` when `trigger=auto` |
| `scripts/client/mac/connect-update.sh` | Added `CLAUDE_CONNECT_UPDATE_QUIET=1` support via `_update_msg`; session id in `_update_file_log` |

**State file:** `$HOME/.config/claude-connect/.last-update-check`

**Flow:** Same throttle/stamp/log contract as Windows. Runs `CLAUDE_CONNECT_UPDATE_QUIET=1 bash "$SCRIPT_DIR/connect-update.sh"`.

### Log lines (both platforms)

```
UPDATE_SILENT skip reason=throttle age_min=N          # DEBUG, no stamp
UPDATE_SILENT age_min=N result=ok exit=0 pending_restart=0
UPDATE_SILENT age_min=N result=fail exit=1 pending_restart=0
UPDATE_SILENT age_min=N result=applied exit=2 pending_restart=1   # WARN
UPDATE_SILENT stamp_fail ...                          # ERROR if state write fails
```

Session id comes from existing `ConnectSessionId` / `CONNECT_SESSION_ID` in log format `[ts] [LEVEL] [sid] message`.

## Verification

Ran `scripts/tmp/verify-silent-update.ps1` on laptop:

```
PASS Invoke-ConnectSilentUpdateCheck exists
PASS throttle log
PASS auto trigger gate
PASS wired in recovery
PASS mac helper / wired / quiet / _update_msg
PASS win Quiet switch
ALL ASSERTS PASS
```

## Not in scope (other agents)

- Pipeline test asserts in `test-connect-pipeline.ps1` (Agent5)
- Mac session-id before bootstrap update (Agent2)
- Rich TUNNEL_DROP fields (Agent3)
