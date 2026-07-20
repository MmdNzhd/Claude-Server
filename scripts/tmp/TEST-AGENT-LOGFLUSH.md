# TEST-AGENT-LOGFLUSH - Hard test (Agent M wave2)

**Date:** 2026-07-20  
**Project:** `-p claude-code-server`  
**Deploy:** none  
**Harness:** `scripts/tmp/test-log-sync-contracts.ps1`  
**Owners:** Win sync = `connect-ui.ps1` (trap in `windows/connect.ps1`); Mac sync = `connect-ui.sh`  
**Verdict:** **PASS**

## Runtime

| Step | Command | Result |
|------|---------|--------|
| Contract harness | `powershell -File scripts/tmp/test-log-sync-contracts.ps1` | exit **0** - pass=8 fail=0 |
| deep-audit-log.ps1 | present; run via `scripts/tmp/run-deep-audit.ps1` + 20260719 log | exit 0 (perf/waste notes only; not contract-blocking) |

## Contract matrix

| # | Contract | Result | Evidence |
|---|----------|--------|----------|
| 1 | Win: no remote cmd ending with `; true` after log append | **PASS** | `$cat = '...; ec=$?; ...; exit $ec'` - no trailing `; true` (bug 11) |
| 2 | Win: watermark/offset advance only inside success branch | **PASS** | `Write-ConnectLogSyncWatermark` only under `if ($appendOk)` after `$catRes.Ok` |
| 3 | Win: trap/Unexpected has Write-Log AND sync/flush | **PASS** | `trap` -> `Write-ConnectLog ... ERROR` + `Wait-ConnectExit` (ERROR Force-syncs) |
| 4 | Win: WARN/ERROR can trigger sync (not TRACE-only forever) | **PASS** | ERROR -> `Sync-ConnectLogToServer -Force`; WARN -> Sync; TRACE local-only except TUNNEL_* |
| 5 | Win: concurrent sync lock OR documented serialization | **PASS** | `.sync-lock` + `ConnectLogSyncInProgress` (bug 72); also single-instance mutex |
| 6 | Mac: no watermark advance after scp alone without cat success | **PASS** | `cat_ok=1` gate; advance only `if [ "$cat_ok" = 1 ]`; remote cat uses `exit $ec` |
| 7 | Mac: bash -n clean on connect.sh + git-mode.sh | **PASS** | Git Bash `bash -n` exit 0 both files |
| 8 | Mac: midnight rollover flushes previous day (rg evidence) | **PASS** | `# Midnight rollover` calls `sync_connect_log_to_server` before `CONNECT_LOG_PATH=` switch (bug 37); Win Ensure uses `-Force -LogPath $prevPath` |

## HARD FAIL - missed contracts

```
(none)
```

## Exit-style verdict

```
VERDICT: PASS
Missed contracts: (none)
=== RESULT pass=8 fail=0 ===
```

No deploy performed.
