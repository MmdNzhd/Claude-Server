# HARD Log Contract Audit

**Date:** 2026-07-20  
**Scope:** `scripts/client/` (Windows + Mac connect/update/UI)  
**Method:** Static code audit via `laptop-exec -p claude-code-server` only  
**Verdict:** **FAIL** (Windows mostly compliant; Mac and UPDATE paths have contract gaps)

---

## Contract Under Test

Every durable log line must match:

```
[ts] [LEVEL] [SESSION_ID] msg
```

Where `ts` = `yyyy-MM-dd HH:mm:ss.fff`, `LEVEL` ∈ {INFO,WARN,ERROR,DEBUG,TRACE}, `SESSION_ID` = 12-char `CLAUDE_CONNECT_RUN_ID` (or `-` fallback).

Additional requirements:
- `SESSION_FILTER` hint + `sessions.index` present after session init
- ERROR/WARN force-sync to server (`~/.claude/logs/connect-YYYYMMDD.log`)
- Required `FAIL *` tags on failure paths
- No `[SESSION_ID]=[-]` when RUN_ID is available
- BOOTSTRAP must not precede RUN_ID assignment

---

## 1. Log Line Format `[ts] [LEVEL] [SESSION_ID] msg`

| Sink | File | Format match | Notes |
|------|------|:------------:|-------|
| **Write-ConnectLog** | `connect-ui.ps1:446-491` | **PASS** | `[$ts] [$Level] [$sid] $Message`; ts with `.fff` |
| **Write-UpdateFileLog** | `connect-update.ps1:62-70` | **PASS*** | Same bracket order; msg prefixed `UPDATE: …` inside body |
| **connect.bat BOOTSTRAP** | `connect.bat:19` | **PASS** | Inline PS: `[{ts}] [INFO] [{sid}] BOOTSTRAP: …`; `.fff` |
| **connect.bat FAIL lines** | `connect.bat:27,35,66` | **PASS** | Same inline format |
| **connect.ps1 pre-init** | `connect.ps1:58-60,505-507` | **PASS** | Direct `AppendAllText` with `.fff` |
| **Mac connect_log** | `connect-ui.sh:219-248` | **FAIL** | Bracket order OK; ts = `%Y-%m-%d %H:%M:%S` **no milliseconds** |
| **Mac BOOTSTRAP** | `connect.sh:20-22` | **FAIL** | Same — second precision only |
| **Mac _update_file_log** | `connect-update.sh:179-182` | **FAIL** | Same — second precision only |
| **Mac flush session end** | `connect-ui.sh:441-446` | **FAIL** | Direct printf, no `.fff` |

**Sub-verdict:** Windows **PASS**; Mac **FAIL** on timestamp precision.

\* UPDATE sinks embed `UPDATE:` in the message body (by design); bracket triple is still correct.

---

## 2. SESSION_FILTER / sessions.index

| Platform | SESSION_FILTER | sessions.index | Verdict |
|----------|----------------|----------------|:-------:|
| **Windows** | `connect-ui.ps1:163` — `SESSION_FILTER grep=[session] …` via Write-ConnectLog (INFO) | `Write-ConnectSessionIndex` → `~/.config/claude-connect/logs/sessions.index` at start (`:166`) and on project/end (`:747`) | **PASS** |
| **Mac** | `connect-ui.sh:514` — `SESSION_FILTER: grep "[session]" … (index: …/sessions.index)` | Tab line appended in `init_connect_log` (`:508-510`) | **PASS** |

Index rows are TSV (not bracket log lines) — acceptable; contract item is presence, not index row format.

---

## 3. ERROR/WARN Force Sync to Server

| Path | Mechanism | Verdict |
|------|-----------|:-------:|
| **Win Write-ConnectLog** | `ERROR` → `Sync-ConnectLogToServer -Force`; `WARN` → `-Force` (`connect-ui.ps1:484-487`) | **PASS** |
| **Mac connect_log** | `ERROR`/`WARN` → `sync_connect_log_to_server force` (`connect-ui.sh:252-254`) | **PASS** |
| **Win Wait-ConnectExit / Close-ConnectLog / trap** | Force sync on non-zero exit and session end | **PASS** |
| **Mac flush_connect_log_to_server / EXIT+ERR traps** | Force sync (`connect-ui.sh:446`, `connect.sh:234-236`) | **PASS** |
| **Win Write-UpdateFileLog** | Append local only; **no** per-line sync | **FAIL** |
| **Mac _update_file_log** | Append local only; **no** sync at all | **FAIL** |
| **connect.bat inline ERROR** | Local append only; ships later when `connect.ps1` calls `Sync-ConnectLogToServer` after SSH config (~`:1055`) | **PARTIAL** — not immediate |
| **Win connect-update ship block** | Best-effort ship only on **exit 2** (success + relaunch), not on exit 1 failures | **FAIL** for failed-update ERROR lines |
| **Mac connect-update** | No server ship block anywhere | **FAIL** |

**Sub-verdict:** Connect-session logging **PASS**; UPDATE-phase ERROR/WARN **FAIL** immediate force-sync contract.

---

## 4. Known Gaps

### 4a. UPDATE lines with session `[-]`

| Scenario | session id | Risk |
|----------|------------|------|
| `connect.bat` / `connect.sh` normal launch | RUN_ID set before BOOTSTRAP/UPDATE | **Low** — real 12-char id |
| `connect.bat` if GUID gen fails | `sid='-'` fallback (`connect.bat:19`) | **Edge** — `[-]` in BOOTSTRAP/FAIL lines |
| `connect.ps1 -File` without bat, pre-`Initialize-ConnectLog` errors | `[-]` (`connect.ps1:59`) | **Medium** — ssh-missing, admin-fix paths |
| Mac `_update_file_log` | `${CLAUDE_CONNECT_RUN_ID:--}` | **Low** when launched via connect.sh (RUN_ID exported first) |
| Mac flat_layout direct printf | `${CLAUDE_CONNECT_RUN_ID:--}` (`connect-update.sh:323`) | **Low** |

**Verdict:** **PARTIAL FAIL** — `[-]` fallback exists in code; rare in bat/sh flow but reachable on direct `connect.ps1` / GUID failure.

### 4b. Early BOOTSTRAP before RUN_ID

| Entry | RUN_ID before BOOTSTRAP? | Verdict |
|-------|--------------------------|:-------:|
| `connect.bat` | Yes — lines 11–14 set `CLAUDE_CONNECT_RUN_ID`, line 19 logs BOOTSTRAP | **PASS** |
| `connect.sh` | Yes — lines 9–15 set/export, lines 20–22 log BOOTSTRAP | **PASS** |
| `connect.ps1 -File` (no bat) | No BOOTSTRAP line at all; RUN_ID assigned in `Initialize-ConnectLog` | **N/A** (gap: missing BOOTSTRAP, not ordering) |
| `connect-update.ps1` standalone | `Ensure-ConnectRunId` at first log call | **PASS** |

**Verdict:** **PASS** for bat/sh ordering; direct-PS launch skips BOOTSTRAP entirely.

### 4c. Pre-`init_connect_log` Mac failures

`die()` before `connect-ui.sh` is sourced (e.g. sudo check `:157`, writable checks `:167`) writes **nothing** to day log except earlier BOOTSTRAP. No FAIL DIE, no sync.

---

## 5. Required FAIL Tags — Coverage Matrix

Required tags: `FAIL EXIT`, `FAIL STEP`, `FAIL NEED_ADMIN`, `FAIL UPDATE_*`, `FAIL DIE`, `FAIL UNHANDLED`.

### Present

| Tag | Where |
|-----|-------|
| **FAIL EXIT** | `connect-ui.ps1:538` — `Wait-ConnectExit` when `$Code -ne 0` |
| **FAIL STEP** | Win `connect.ps1:136`; Mac `connect.sh:102` |
| **FAIL DIE** | Win `connect.ps1:82`; Mac `connect.sh:57` |
| **FAIL UNHANDLED** | Win `connect.ps1:37` (trap) |
| **FAIL NEED_ADMIN** | Win `connect.ps1:372` |
| **FAIL UPDATE_BAT_EXIT** | `connect.bat:27` |
| **FAIL UPDATE_RELAUNCH_LIMIT** | `connect.bat:35` |
| **FAIL UPDATE_UNHANDLED** | `connect-update.ps1:77` |
| **FAIL UPDATE_SWAP_IN_USE** | `connect-update.ps1:531` |

### Missing from paths that can fire

| Tag | Platform | Firing paths without tag | Severity |
|-----|----------|--------------------------|----------|
| **FAIL EXIT** | **Mac** | All `exit 1` without `die()` — e.g. cannot reach server (`:309`), foreign session abort (`:346`), init server fail (`:363`), ssh key fail (`:261`), Remote Login fail (`:251`), project fail, etc. | **HIGH** |
| **FAIL UNHANDLED** | **Mac** | ERR/EXIT traps log `UNHANDLED: …` only (`connect.sh:234-236`), not `FAIL UNHANDLED:` | **MEDIUM** |
| **FAIL NEED_ADMIN** | **Mac** | N/A (no Windows admin-key model); Mac uses sudo/Remote Login — no equivalent tag | **N/A** (platform) |
| **FAIL UPDATE_*** | **Mac** | All update failures use bare messages: `download_failed`, `manifest_empty_or_unreachable`, `checksum_fail`, `apply_rollback`, etc. (`connect-update.sh`) — **zero** `FAIL UPDATE_*` prefixes | **HIGH** |
| **FAIL UPDATE_*** | **Win** | Most `Write-UpdateFileLog` ERROR paths lack `FAIL UPDATE_*` (e.g. `download_failed`, `manifest_empty_or_unreachable`, `checksum_verify_failed`, `swap_fail`, `copy_fail`) — only UNHANDLED, SWAP_IN_USE, and bat-level tags | **MEDIUM** |
| **FAIL EXIT** | **Win** | Early `exit 1` before `Wait-ConnectExit` loads (ssh missing `:68`) — logs ERROR but not `FAIL EXIT` | **LOW** |

Extra Win tags (not in required list but present): `FAIL ADMIN_DENIED`, `FAIL ADMIN_UAC`, `FAIL ADMIN_FIX`, `FAIL OUTDATED_SCRIPTS`.

---

## 6. SSH "unexpected EOF while looking for matching …" Quoting Glitch

| Behavior | Location | Logged as |
|----------|----------|-----------|
| **Root cause fixed** | Mac `sshx()` base64-wrap (`connect.sh:107-115`) — comment cites old quoting bug | — |
| **Filtered silently** | `warn_foreign_server_session` treats `*"unexpected EOF"*` in parsed laptop user as empty → return 0 (`git-mode.sh:1579`) | **No log** when filter matches |
| **SSH command failure** | `SSH_END exit=N … out=…unexpected EOF…` | **INFO** only — default level on `Write-ConnectLog` / `connect_log` (`connect.ps1:677`, `connect.sh:142`) |
| **Dedicated FAIL tag** | — | **None** |

**Verdict:** Quoting glitches surface as **INFO `SSH_END`** (if ssh returns output), or **silenced** in foreign-session probe — **never `FAIL`**.

---

## Summary Table

| # | Requirement | Win | Mac | Overall |
|---|-------------|:---:|:---:|:-------:|
| 1 | Bracket log format | PASS | FAIL (no `.fff`) | **FAIL** |
| 2 | SESSION_FILTER + sessions.index | PASS | PASS | **PASS** |
| 3 | ERROR/WARN force sync (connect_log) | PASS | PASS | **PASS** |
| 3b | ERROR/WARN force sync (UPDATE sinks) | FAIL | FAIL | **FAIL** |
| 4a | Session `[-]` gaps | PARTIAL | PARTIAL | **PARTIAL** |
| 4b | BOOTSTRAP after RUN_ID | PASS | PASS | **PASS** |
| 5 | Required FAIL tags | PARTIAL | FAIL | **FAIL** |
| 6 | unexpected EOF → FAIL | FAIL | FAIL | **FAIL** |

---

## Recommended Fixes (priority order)

1. **Mac timestamp parity** — use `%Y-%m-%d %H:%M:%S.$(printf '%03d' $(( $(date +%N 2>/dev/null || echo 0) / 1000000 )))` or Python/ms helper in `connect_log`, bootstrap, `_update_file_log`, flush.
2. **Mac FAIL EXIT** — wrap terminal exits (or add `wait_connect_exit` parity) after `init_connect_log`.
3. **Mac FAIL UNHANDLED** — append `FAIL UNHANDLED:` in ERR trap alongside existing `UNHANDLED:`.
4. **FAIL UPDATE_*** — prefix all update ERROR exits on both platforms (`FAIL UPDATE_DOWNLOAD`, `FAIL UPDATE_CHECKSUM`, etc.).
5. **Write-UpdateFileLog / _update_file_log** — on ERROR/WARN, invoke same force-sync path as connect_log (or ship-on-exit for exit 1 as well as exit 2).
6. **SSH quoting failures** — if `SSH_END` out matches `unexpected EOF|syntax error`, emit additional `FAIL SSH_QUOTE:` at ERROR level.

---

*Generated by static audit; no runtime log capture.*
