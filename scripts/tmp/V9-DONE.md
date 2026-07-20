# Agent V9 — session log contract tests

**Date:** 2026-07-20  
**Scope:** tests only (`test-connect-pipeline.ps1` additive asserts + `test-session-log-contracts.ps1`)  
**Deploy:** none

## Pipeline run

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/client/tests/test-connect-pipeline.ps1
```

**Result:** FAIL (exit 1) — **1** contract assert missing in source (other agents still editing)

## Passing contracts (24/25 in V9 suite)

| Contract | Status |
|---|---|
| `CLAUDE_CONNECT_RUN_ID` in `connect.bat` | PASS |
| `CLAUDE_CONNECT_RUN_ID` in `mac/connect.sh` (before update hook) | PASS |
| `sessions.index` (Win + Mac) | PASS |
| `SESSION_FILTER` (Win + Mac) | PASS |
| `Get-ConnectSessionId` / `connect_session_id` | PASS |
| `Invoke-ConnectSilentUpdateCheck` / `invoke_connect_silent_update_check` / `UPDATE_SILENT` | PASS |
| Quiet / `CLAUDE_CONNECT_UPDATE_QUIET` | PASS |
| `TUNNEL_DROP` (git-mode + connect-ui, Win + Mac) | PASS |
| `Begin-ConnectRecovery` present | PASS |
| manual recovery does not call silent update | PASS |
| `begin_connect_recovery` (Mac) | PASS |

## Missing asserts (source not ready)

1. **auto recovery path references silent update (best-effort)** — `Begin-ConnectRecovery -Trigger 'auto'` block in `windows/connect.ps1` does not yet call `Invoke-ConnectSilentUpdateCheck` / `UPDATE_SILENT` within ~3000 chars of the call site. Other agents likely still wiring silent update into auto recovery.

## Files touched (V9)

- `scripts/client/tests/test-connect-pipeline.ps1` — V9 additive asserts + dot-sources session contract suite
- `scripts/client/tests/test-session-log-contracts.ps1` — new standalone + dot-sourced contract suite

## Next

Re-run pipeline test after auto-recovery silent-update wiring lands; expect green when `Begin-ConnectRecovery -Trigger 'auto'` invokes silent check.
