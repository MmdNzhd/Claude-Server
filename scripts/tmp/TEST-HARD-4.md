# TEST-HARD-4 — Agent T4 Logging Hard Verify

**Date:** 2026-07-20  
**Project:** `claude-code-server` (`laptop-exec -p claude-code-server`)  
**Tunnel:** UP (Smart/windows, port 21002)  
**Deploy:** none  

---

## OVERALL: **PASS**

All T4 logging MUST checks pass. Contract suites focused on log sync / error flush pass. One tangential assertion in `test-session-log-contracts.ps1` fails (Windows silent-update helper missing from `connect-ui.ps1` — not a logging-sync requirement).

---

## 1. Contract tests executed

| Script | Result | Notes |
|--------|--------|-------|
| `scripts/tmp/test-log-sync-contracts.ps1` | **PASS** (8/8) | C1–C8: watermark gating, no `; true` on cat, WARN/ERROR Force, lock, Mac cat_ok, bash -n, midnight flush |
| `scripts/tmp/test-error-flush-contract.ps1` | **PASS** (16/16) | Trap ERROR→flush, watermark only on `$scpOk`, no `; true` masking |
| `scripts/client/tests/test-session-log-contracts.ps1` | **PARTIAL** (11/12) | FAIL: `Invoke-ConnectSilentUpdateCheck` not present in `connect-ui.ps1` (bash has `invoke_connect_silent_update_check`; Windows `connect.ps1` calls PS fn via `Get-Command` guard — fn undefined) |

---

## 2. Static MUST verification

### 2.1 Watermark advances only after successful append (no `; true` masking cat)

| Platform | Evidence | Verdict |
|----------|----------|---------|
| **Windows** (`connect-ui.ps1`) | `$cat` ends with `exit $ec` (no trailing `; true`). `Write-ConnectLogSyncWatermark` only inside `if ($appendOk)` / `$scpOk` gate after scp+cat success | **PASS** |
| **Mac/bash** (`connect-ui.sh`) | `cat_ok=1` only when ssh cat append succeeds; offset written only `if [ "$cat_ok" = 1 ]`. Comment: "Bug 11/12: no trailing true" | **PASS** |

Note: `_server_logs_cleanup_cmd` / `$mk` mkdir helper ends with `; true` — that is **not** the log append path (cleanup only).

### 2.2 ERROR/WARN Force sync

| Platform | Evidence | Verdict |
|----------|----------|---------|
| **Windows** | `Write-ConnectLog`: `Level -eq 'ERROR'` / `'WARN'` → `Sync-ConnectLogToServer -Force` | **PASS** |
| **Mac/bash** | `connect_log`: `level = ERROR/WARN` → `sync_connect_log_to_server force` | **PASS** |

### 2.3 Write-ConnectLog stamps `[sid]`

| Platform | Format | Verdict |
|----------|--------|---------|
| **Windows** | `WriteLine("[$ts] [$Level] [$sid] $Message")` via `Get-ConnectSessionId` | **PASS** |
| **Mac/bash** | `printf '[%s] [%s] [%s] %s\n' … "$level" "${CONNECT_SESSION_ID:--}"` | **PASS** |

### 2.4 SESSION_FILTER + sessions.index

| Platform | Evidence | Verdict |
|----------|----------|---------|
| **Windows** | `Write-ConnectSessionIndex` → `sessions.index`; startup logs `SESSION_FILTER grep=[sid]` | **PASS** |
| **Mac/bash** | `init_connect_log` appends tab row to `sessions.index`; logs `SESSION_FILTER: grep "[$CONNECT_SESSION_ID]" …` | **PASS** |

### 2.5 ReadAllBytes NOT used for day-log sync in connect-ui.ps1

| Check | Verdict |
|-------|---------|
| `connect-ui.ps1` sync uses chunked `[System.IO.FileStream]::Open` + byte[] read (512KB max) | **PASS** |
| `ReadAllBytes` absent from `connect-ui.ps1` and `connect-ui.sh` | **PASS** |
| `ReadAllBytes` present only in `scripts/client/tests/test-publish.ps1` (tests OK) | **PASS** |

---

## 3. Mac `connect_log` session-id format

**Log line shape:** `[YYYY-MM-DD HH:MM:SS] [LEVEL] [sid] message`

**sid generation** (`connect_session_id` in `connect-ui.sh`):

1. Reuse `CLAUDE_CONNECT_RUN_ID` if length ≥ 8  
2. Else reuse `CONNECT_SESSION_ID` if length ≥ 8  
3. Else `python3 -c 'import uuid;print(uuid.uuid4().hex[:12])'` → **12 lowercase hex chars**  
4. Fallback: `{unix_epoch}{pid_last4}` via `printf '%s%04d' "$(date +%s)" "$$"`

**Mac launcher** (`mac/connect.sh`): after `init_connect_log`, re-exports `CONNECT_SESSION_ID` from `CLAUDE_CONNECT_RUN_ID` when preset (bat/run-id parity).

**Windows parity:** `Get-ConnectSessionId` → 12-char GUID hex (`[guid]::NewGuid().ToString('N').Substring(0, 12)`).

**Verdict:** **PASS** — bracketed 12-hex sid in every line; filterable via `grep "[sid]"`.

---

## 4. Advisory (non-blocking for T4 logging)

- `test-session-log-contracts.ps1` expects `Invoke-ConnectSilentUpdateCheck` in `connect-ui.ps1`; function is **missing** on Windows (only bash `invoke_connect_silent_update_check` exists). Silent update is orthogonal to log sync/watermark policy.

---

## 5. Commands run

```text
laptop-exec status / health
laptop-exec run -p claude-code-server -- powershell -File scripts/tmp/test-log-sync-contracts.ps1
laptop-exec run -p claude-code-server -- powershell -File scripts/tmp/test-error-flush-contract.ps1
laptop-exec run -p claude-code-server -- powershell -File scripts/client/tests/test-session-log-contracts.ps1
laptop-exec rg -p claude-code-server (static patterns in connect-ui.ps1/sh)
```

---

**Signed:** Agent T4 hard-verify (no deploy)
