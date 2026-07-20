# HARD-GAP: Orphan User-Visible Failures (Console-Only Bugs)

**Audit date:** 2026-07-20  
**Scope:** `scripts/client/windows/connect.ps1`, `connect-ui.ps1`, `windows/connect-update.ps1`, `windows/connect.bat`, `mac/connect.sh`, `connect-ui.sh`, `users/designer/*`  
**Method:** Static trace of `[X]` / red failure UI, `StepFail`/`step_fail`, and non-zero exits vs day-log `ERROR`/`FAIL` lines (`connect-YYYYMMDD.log` via `Write-ConnectLog` / `connect_log` / bootstrap append).

## Overall verdict: **FAIL**

Orphan failure paths remain that a user can hit. Main Windows developer connect is largely wired; Mac lacks `FAIL EXIT` entirely; designer launchers have no day-log integration for failures.

---

## Orphan paths (by file)

### `scripts/client/windows/connect.bat`

| Path | User sees | Day log | Gap |
|------|-----------|---------|-----|
| OUTDATED package guard (~L67–79) | `[X] OUTDATED scripts in this folder.` + pause | **None** (no `ERROR`/`FAIL` append before `exit /b 1`) | Console-only; operator cannot grep day log |

**Note:** Update relaunch limit in the same file **does** log `FAIL UPDATE_RELAUNCH_LIMIT` — not an orphan.

---

### `scripts/client/mac/connect.sh`

Mac has no `Wait-ConnectExit` / `FAIL EXIT` helper (Windows-only in `connect-ui.ps1`). Early fatal exits rely on `die()` (`FAIL DIE`) or EXIT-trap `UNHANDLED: exit=N` (`ERROR`, not `FAIL EXIT`).

| Path | User sees | Day log | Gap |
|------|-----------|---------|-----|
| Early auto-update relaunch cap (~L32) | `[X] Update relaunch limit reached - continuing with current files.` | **None** (unlike `connect.bat`, which writes `FAIL UPDATE_RELAUNCH_LIMIT`) | `[X]` without `ERROR`/`FAIL` |
| Server unreachable (~L305–309) | `[!] Cannot reach …` then blank line exit | EXIT trap: `UNHANDLED: exit=1` only | No `step_fail`, no `FAIL EXIT`, no `FAIL DIE` |
| Foreign-session abort (~L345–346) | `[!] Aborted. Fix username…` then `exit 1` | `warn` → `WARN` only; EXIT trap `UNHANDLED: exit=1` | No `FAIL EXIT`; abort is WARN-only in log |
| No editor after project pick (~L591–593) | `[!] No editor found…` then `exit 1` | EXIT trap `UNHANDLED: exit=1` only | No `step_fail`, no `FAIL EXIT` |
| Remote Login enable fail in session loop (~L661–667) | `step_fail` → ` failed` + `Could not enable Remote Login…` | `step_fail` → `FAIL STEP` (`ERROR`) | User-visible hard stop, but script returns to menu with **exit 0** — no `FAIL EXIT` |
| All other bare `exit 1` (~L251, L261, L339, L363, …) | `step_fail` / `warn` / blank line | `FAIL STEP` and/or `UNHANDLED: exit=1` | Missing **`FAIL EXIT reason=…`** (platform gap vs Windows) |

`die()` paths (~L54–62) are **not** orphans: they write `FAIL DIE`.

---

### `scripts/client/connect-ui.ps1` + `scripts/client/connect-ui.sh`

| Item | Notes |
|------|-------|
| `Write-ConnectUserFacingError` | Defined in `connect-ui.ps1` (~L513) with comment “Every red [X] MUST land in day log” — **never called** anywhere in scoped tree |
| `Wait-ConnectExit` | Windows-only; writes `FAIL EXIT` — **not ported to Mac/bash** |
| `connect-ui.sh` | No `[X]` helper, no `FAIL EXIT`, no `USER_ERROR` wrapper |

Not a direct user-hit orphan by itself, but explains why Mac `[X]`/`die()` paths skip `USER_ERROR:` tagging.

---

### `scripts/client/windows/connect-update.ps1`

| Path | User sees | Day log | Gap |
|------|-----------|---------|-----|
| `trap` (~L72–79) | `[X] Update error: …` | `FAIL UPDATE_UNHANDLED` (`ERROR`) via `Write-UpdateFileLog` | **Logged** — not orphan |
| `exit 1` paths (~L296+, manifest/download/checksum/apply) | `[!] Update download failed…` (some) or silent | `Write-UpdateFileLog …` `ERROR` (not always `FAIL` prefix) | Meets `ERROR` criterion; **`FAIL UPDATE_*` prefix inconsistent** |

`connect.bat` adds `FAIL UPDATE_BAT_EXIT` when update returns 1 — covered.

---

### `scripts/client/windows/connect.ps1`

Main developer launcher is **mostly wired**:

- `Die()` → `FAIL DIE` + `Wait-ConnectExit`
- `StepFail` → `FAIL STEP` (`ERROR`)
- Fatal paths → `Wait-ConnectExit` → `FAIL EXIT`
- Pre-UI ssh missing / trap / admin-fix → manual `FAIL …` bootstrap append

**No user-hit orphan** found in scoped fatal paths. Session-loop `StepFail` (tunnel/mount/auth) logs `FAIL STEP` even when user retries (by design).

---

### `scripts/client/users/designer/connect.ps1`

Designer dot-sources `connect-ui.ps1` and calls `Initialize-ConnectLog`, but **local `Die` / `StepFail` defined earlier never delegate to `Write-ConnectLog` or `Wait-ConnectExit`**.

| Path | User sees | Day log | Gap |
|------|-----------|---------|-----|
| OpenSSH client missing (~L17–19) | `[X] OpenSSH client (ssh.exe) not found.` | **None** (runs before `Initialize-ConnectLog`) | Console-only |
| `Die()` (~L34, calls at L132, L202, L210–211, L388, L392, L405, L407) | `[X] …` | **None** | No `FAIL DIE` / `USER_ERROR` |
| `StepFail` (~L43–48; all call sites) | ` failed` + detail | **None** | Local helper is console-only (not WARN — **no log at all**) |
| Bare `exit 1` after `StepFail` (~L229, L271, L290, L301–302) | same as above | **None** | No `FAIL EXIT` |
| Session tunnel/mount/noVNC `StepFail` (~L526, L551) | ` failed` + retry menu | **None** | Console-only step failures |

---

### `scripts/client/users/designer/connect.sh`

No `connect-ui` / day log integration.

| Path | User sees | Day log | Gap |
|------|-----------|---------|-----|
| `die()` (~L17; calls L39, L48, L97, L102–103, L207) | `[X] …` | **None** | Console-only |
| `step_fail()` (~L25) | ` failed` + detail | **None** | Unlike main `mac/connect.sh`, **no** `connect_log`/`FAIL STEP` |
| Bare `exit 1` (~L114, L124, L170, L187, L197–199) | warnings + exit | **None** | No `FAIL EXIT` |

---

## Summary counts

| Area | Orphan user-hit paths |
|------|----------------------|
| `connect.bat` OUTDATED | 1 |
| `mac/connect.sh` | 6+ (incl. platform `FAIL EXIT` gap on all bare exits) |
| `users/designer/*` | **All** `Die`/`step_fail`/fatal exits (~20+ sites) |
| Main `connect.ps1` (Windows dev) | 0 |
| `connect-update.ps1` | 0 (ERROR present; `FAIL` prefix optional) |

---

## Recommended fixes (priority)

1. **`connect.bat` OUTDATED:** Append `[ERROR] FAIL OUTDATED_SCRIPTS: …` to day log (mirror bootstrap pattern used for update failures).
2. **`mac/connect.sh` update relaunch cap:** Append `FAIL UPDATE_RELAUNCH_LIMIT` to bootstrap/day log (parity with `connect.bat` ~L35).
3. **Mac fatal exits:** Add `wait_connect_exit()` in `connect-ui.sh` (write `FAIL EXIT reason=…`) and call from `die()`, foreign-session abort, unreachable server, no-editor exit, etc.
4. **Mac `[X]` / early failures:** Route through `write_connect_user_error()` or ensure `FAIL DIE` before any `[X]`.
5. **Designer launchers:** Replace local `Die`/`StepFail` with shared helpers from `connect-ui` (or call `Write-ConnectLog` + `Wait-ConnectExit` / `FAIL DIE` + `FAIL STEP`).
6. **Wire `Write-ConnectUserFacingError`:** Use for every `[X]` in Windows `connect.ps1` `Die`/trap for grep-able `USER_ERROR:` lines.

---

## PASS criteria check

> Overall PASS only if no orphans remain that a user could hit.

**Result: FAIL** — `connect.bat` OUTDATED, Mac early/update/foreign-session/editor exits, and the entire designer package remain console-only for failures.
