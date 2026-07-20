# HARD Logging Audit — Mac + Designer

**Date:** 2026-07-20  
**Auditor:** agent (laptop-exec `-p claude-code-server`)  
**Standard:** Same as Windows — every user-visible red `[X]`, `die`, `step_fail`, or terminating `exit 1` must produce a **day log line** at **`ERROR`** level with a **`FAIL` prefix** and bracketed **session id** (`[session]`).

**Log sink:** `~/.config/claude-connect/logs/connect-YYYYMMDD.log` (+ server sync to `~/.claude/logs/`)

**Scope files:**
| Path in scope | On-disk path (laptop) | Notes |
|---|---|---|
| `scripts/client/mac/connect.sh` | ✓ | Main Mac launcher |
| `scripts/client/connect-ui.sh` | ✓ | Shared Mac UI + `connect_log()` |
| `scripts/client/mac/connect-update.sh` | ✓ | Pre-init auto-update |
| `scripts/client/git-mode.sh` | ✓ | Shared helpers |
| `scripts/client/editor-launch.sh` | ✓ | Shared editor launch |
| `users/designer/connect.sh` | **`scripts/client/users/designer/connect.sh`** | `users/designer/` not at repo root |
| `users/designer/connect.ps1` | **`scripts/client/users/designer/connect.ps1`** | Published as `designer/connect.ps1` |

---

## Executive summary

| Area | Verdict |
|---|---|
| Mac `connect.sh` + `connect-ui.sh` | **FAIL** — helpers exist (`die`/`step_fail`/`FAIL DIE`/`FAIL STEP`) but multiple terminating paths and bootstrap/update gaps remain |
| Mac `connect-update.sh` | **FAIL** — logs `UPDATE:` at ERROR without `FAIL` prefix; 3 bare `exit 1` orphans |
| `git-mode.sh` (Mac path) | **FAIL** — several ERROR lines lack `FAIL` prefix; diag `_dlog` uses WARN |
| `editor-launch.sh` | **FAIL** (minor) — user errors return 1 with `warn` only |
| Designer Mac `connect.sh` | **FAIL** — **no** `connect-ui.sh`, **no** `connect_log` / `init_connect_log`; all helpers are printf-only |
| Designer Windows `connect.ps1` | **FAIL** — sources `connect-ui.ps1` + `Initialize-ConnectLog`, but **local** `Die`/`StepFail` never call `Write-ConnectLog` |

### Overall verdict: **FAIL**

Mac main connect is partially instrumented (good `die`/`step_fail` pattern vs Windows), but the audit standard is not met end-to-end. Designer scripts are effectively unlogged for failure paths.

---

## Contract (Windows reference)

Windows `connect.ps1` pattern (target):

```powershell
Write-ConnectLog "ERROR: $m" 'ERROR'
Write-ConnectLog "FAIL DIE: $m" 'ERROR'

Write-ConnectLog "STEP end: ... failed ..." 'ERROR'
Write-ConnectLog ("FAIL STEP name={0} detail={1}" -f ...) 'ERROR'
```

Mac equivalents in `scripts/client/mac/connect.sh`:

```bash
connect_log "ERROR: $*" 'ERROR'
connect_log "FAIL DIE: $*" 'ERROR'

connect_log "STEP end: $CURRENT_STEP_NAME failed ..." 'ERROR'
connect_log "FAIL STEP name=$CURRENT_STEP_NAME detail=$detail" 'ERROR'
```

Day log line format from `connect-ui.sh`:

```
[YYYY-MM-DD HH:MM:SS] [ERROR] [session_id] FAIL STEP name=... detail=...
```

---

## 1. `scripts/client/connect-ui.sh`

| Check | Result | Evidence |
|---|---|---|
| Session id in log lines | **PASS** | `connect_log()` prints `[${CONNECT_SESSION_ID:--}]` (L219–241) |
| ERROR/WARN force sync | **PASS** | ERROR/WARN call `sync_connect_log_to_server force` |
| `FAIL EXIT` helper (Windows parity) | **FAIL** | No Mac `connect_log_exit` / `FAIL EXIT` helper (Windows has `Write-ConnectLog "FAIL EXIT ..."` in `connect-ui.ps1`) |
| Silent update errors | **PARTIAL PASS** | `UPDATE_SILENT ... result=fail` logged ERROR (L300) but message uses `UPDATE_SILENT`, not `FAIL UPDATE` |

**Verdict:** **FAIL** (missing exit helper; update tag not `FAIL`-prefixed)

---

## 2. `scripts/client/mac/connect.sh`

### PASS — wired correctly (post-`init_connect_log`, L221)

| Mechanism | Logs | Session id |
|---|---|---|
| `die()` L54–62 | `ERROR:` + `FAIL DIE:` + flush | ✓ after init |
| `step_fail()` L97–104 | `STEP end ... failed` + `FAIL STEP` | ✓ after init |
| EXIT trap L234 | `UNHANDLED: exit=$ec` ERROR on nonzero | ✓ but **no `FAIL` prefix** |

### FAIL — orphans / non-compliant

| Line | User signal | What hits day log | Gap |
|---|---|---|---|
| **L20–22** | (bootstrap) | `[INFO] [run_id] BOOTSTRAP: connect.sh start` | Pre-init; not ERROR/FAIL |
| **L32** | `[X] Update relaunch limit reached` | **nothing** (printf only) | No ERROR/FAIL; pre-`init_connect_log` |
| **L157–177** | `die` sudo / writable checks | **nothing** (`connect_log` not sourced yet) | Orphan — only bootstrap INFO exists |
| **L186–216** | `die` setup / missing includes | **nothing** (`CONNECT_LOG_PATH` unset → `connect_log` no-op) | Orphan until L221 |
| **L309** | `exit 1` after reachability failure | EXIT trap → `UNHANDLED: exit=1` (if past init) | No `FAIL`; only `warn` (WARN) before exit |
| **L324–339** | `step_fail` + `exit 1` SSH verify | `FAIL STEP` ✓ then `UNHANDLED: exit=1` | No explicit `FAIL EXIT` |
| **L346** | `exit 1` foreign-session abort | `warn` only + `UNHANDLED: exit=1` | No `FAIL FOREIGN_SESSION` / `FAIL EXIT` |
| **L593** | `exit 1` no editor | `warn` + `UNHANDLED: exit=1` | No `FAIL` prefix |

**Evidence L309:**
```bash
warn "Cannot reach $SERVER_IP after 10 attempts"
warn "VPN connected? Server running?"
echo ""; exit 1
```

**Evidence L346:**
```bash
if ! warn_foreign_server_session; then
    exit 1
fi
```

**Verdict:** **FAIL** (6+ terminating/orphan paths; EXIT trap uses `UNHANDLED`, not `FAIL`)

---

## 3. `scripts/client/mac/connect-update.sh`

Runs **before** `init_connect_log` (invoked connect.sh L25–37). Uses `_update_file_log`:

```bash
printf '[%s] [%s] [%s] UPDATE: %s\n' ... "$level" "$sid" "$msg"
```

| Check | Result | Evidence |
|---|---|---|
| Session id | **PASS** | Uses `CLAUDE_CONNECT_RUN_ID` (L181–182) |
| ERROR on hard failures | **PARTIAL** | Many paths log `UPDATE: ...` at ERROR |
| **`FAIL` prefix** | **FAIL** | Tag is `UPDATE:`, never `FAIL UPDATE:` or `FAIL ...` |
| Bare `exit 1` without log | **FAIL** | **L290** (checksum verify fail), **L374** (copy loop — prior line logs but no FAIL), **L398** (mac rollback — prior line logs but no FAIL) |

**Evidence L287–290:**
```bash
if ! _verify_checksums "$STAGING_DIR"; then
    _update_msg '  [!] Update checksum failed - using local copy\n'
    rm -rf "$STAGING_DIR"
    exit 1   # <-- no _update_file_log
fi
```

**Verdict:** **FAIL**

---

## 4. `scripts/client/git-mode.sh` (Mac connect sources this)

| Path | User / ops signal | Day log | Gap |
|---|---|---|---|
| `PUSH_CONF fail` L140 | push failure | ERROR `PUSH_CONF fail exit=...` | No `FAIL PUSH_CONF` prefix |
| `INIT_SERVER_SESSION fail` L1638+ | init failure | ERROR `INIT_SERVER_SESSION fail=...` | No `FAIL INIT_SERVER_SESSION`; Mac connect also calls `step_fail` afterward ✓ |
| `_dlog "FAIL reason=..."` L605–609 | SSH diag | `LAPTOP_SSH_DIAG: FAIL reason=...` at **WARN** | Should be ERROR + `FAIL LAPTOP_SSH` for hard standard |
| `warn_foreign_server_session` abort L1619–1621 | user abort | `warn` only | No `FAIL FOREIGN_SESSION` |
| Tunnel/mount soft fails | retry paths | WARN/TRACE | Acceptable (non-terminating) |

**Verdict:** **FAIL** (ERROR lines missing required `FAIL` prefix; diag FAIL at WARN)

---

## 5. `scripts/client/editor-launch.sh`

| Line | Signal | Logging |
|---|---|---|
| L30 | `warn 'Invalid choice.'; return 1` | No `connect_log` ERROR/FAIL (optional `connect_log` exists for LAUNCH_* INFO only) |
| L41,96,104,117,121,130,147 | silent `return 1` | No user `[X]`; no log |

Shared helper pattern: `declare -F connect_log` guard — **never logs failures**.

**Verdict:** **FAIL** (minor — few user-visible errors, no FAIL logging)

---

## 6. Designer — `scripts/client/users/designer/connect.sh`

### Critical: helpers never call `connect_log`

```bash
die()       { echo ""; echo "  [X] $*"; echo ""; exit 1; }
step_fail() { printf ' failed\n'; [ -n "${1:-}" ] && printf '      -> %s\n' "$*"; }
```

- **Does not source** `connect-ui.sh`
- **Does not call** `init_connect_log`
- Sources `git-mode.sh` L207 — git-mode *would* log **if** `connect_log` existed, but it never gets defined in designer session

| Line | Terminating path | Day log |
|---|---|---|
| L17 / L39–49 | `die` | **none** |
| L114 | Remote Login enable fail | **none** |
| L124 | key create fail | **none** |
| L170 | server unreachable | **none** |
| L187 | SSH verify fail | **none** |
| L197–199 | port/key fail | **none** |

**Verdict:** **FAIL** — designer Mac is a complete logging orphan for all failure UI

---

## 7. Designer — `scripts/client/users/designer/connect.ps1`

Sources shared UI (L143–147):

```powershell
. $_connectUi
Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version 'designer'
```

But **local** helpers override Windows pattern:

```powershell
function Die($m)  { Write-Host "  [X] $m" ...; exit 1 }   # no Write-ConnectLog
function StepFail { Write-Host " failed" ... }             # no Write-ConnectLog
```

| Line | Signal | Write-ConnectLog / FAIL |
|---|---|---|
| L17–19 | `[X] ssh.exe not found` + `exit 1` | **none** (before UI init) |
| L34 Die() | all `Die` calls | **none** |
| L43 StepFail() | all step failures | **none** |
| git-mode.ps1 helpers | various | May log **if** `Write-ConnectLog` exists — session id present, but Die/StepFail paths bypass |

**Verdict:** **FAIL** — `Initialize-ConnectLog` runs, yet designer-local Die/StepFail never write FAIL lines

---

## Orphan summary table

| ID | File | Line(s) | Missing |
|---|---|---|---|
| O1 | mac/connect.sh | 157–216 | Any day log on early `die` |
| O2 | mac/connect.sh | 32 | `[X]` update relaunch cap |
| O3 | mac/connect.sh | 309, 346, 593 | `FAIL ...` ERROR before `exit 1` |
| O4 | mac/connect.sh | 234 EXIT trap | Uses `UNHANDLED:` not `FAIL EXIT:` |
| O5 | mac/connect-update.sh | 290, 374, 398 | ERROR log line (290 has none) |
| O6 | mac/connect-update.sh | all ERROR paths | `FAIL` prefix (uses `UPDATE:`) |
| O7 | git-mode.sh | 140, 1638+ | `FAIL` prefix on ERROR |
| O8 | git-mode.sh | 605–609 via `_dlog` | ERROR + `FAIL LAPTOP_SSH` (currently WARN) |
| O9 | editor-launch.sh | 30+ | FAIL log on user error |
| O10 | designer/connect.sh | all | Entire script — no connect_log |
| O11 | designer/connect.ps1 | Die/StepFail | Write-ConnectLog + FAIL prefix |

---

## Recommended fixes (priority)

1. **Designer (highest):** Source `connect-ui.sh` / `connect-ui.ps1`; replace local `die`/`Die`/`step_fail`/`StepFail` with shared implementations (or call `connect_log`/`Write-ConnectLog` + `FAIL` prefix inside them).
2. **Mac connect.sh:** Add `connect_log_fail_exit "reason"` before every bare `exit 1`; map foreign-session abort + unreachable server + no-editor.
3. **Mac connect-update.sh:** Prefix hard errors `FAIL UPDATE: ...`; log L290 checksum failure.
4. **git-mode.sh:** Rename/init errors to `FAIL INIT_SERVER_SESSION`, `FAIL PUSH_CONF`; promote diag `_dlog` FAIL lines to ERROR.
5. **connect-ui.sh:** Add Mac `connect_log_exit` mirroring Windows `FAIL EXIT`.

---

## Audit method

- Static review via `laptop-exec read` / `laptop-exec rg` on laptop disk (no `/mounts/` Read/Grep)
- Compared against Windows `scripts/client/windows/connect.ps1` + `connect-ui.ps1` Die/StepFail/Write-ConnectLog patterns
- Traced `init_connect_log` call order vs pre-init bootstrap/update

