# FIX-WIN-P1 — Windows remaining P1

Date: 2026-07-20  
Scope: `connect.ps1` / `connect-ui.ps1` / designer / `connect-update.ps1`  
Constraints: laptop-exec only (`-p claude-code-server`); **no deploy**; **do not** revert `git-mode.ps1` `banner_miss_tcp_open_budget` or Ensure `action=reseed` (still present at `git-mode.ps1:534`, `:913`).

| # | Item | Result | Notes |
|---|------|--------|-------|
| 1 | EditorSeenOpen sticky | **PASS** | Clear on editor closed; never force `editorOpened` from sticky alone |
| 2 | Trap / Unexpected flush | **PASS** | `Write-ConnectLog … 'ERROR'` + `Sync-ConnectLogToServer -Force` before exit |
| 3 | Log watermark | **PASS** | Watermark advances only when `$appendOk` |
| 4 | Designer forks | **PASS** (mutex fallback strengthened this pass) | useVk + `-ClearActiveMount` + always-on mutex |
| 5 | connect-update | **PASS** | ERROR → `exit 1`; staged swap + rollback on apply fail |

---

## 1. EditorSeenOpen sticky — PASS

**File:** `scripts/client/windows/connect.ps1`

- On closed editor (not on-folder **and** no window): log `EDITOR_SEEN_CLEAR` and set `$script:EditorSeenOpen = $false` at session_open / session_poll / auto_recovery / finally.
- Poll path sets `$editorOpened = $false` when not on-folder; sticky alone does **not** assign `$editorOpened = $true`.
- Auto-recovery comment + logic: *“never force editorOpened from sticky alone”* (~L1740). Sticky may still skip mount-clear only when window is open or CIM check failed.

Evidence:

```
EDITOR_SEEN_CLEAR … phase=session_open|session_poll|auto_recovery|finally
# Keep EditorSeenOpen if already set … never force editorOpened from sticky alone.
```

No remaining `elseif ($script:EditorSeenOpen) { $editorOpened = $true }` pattern.

---

## 2. Trap / Unexpected — PASS

**File:** `scripts/client/windows/connect.ps1` trap (~L31–50)

1. `Write-ConnectLog "UNHANDLED: …" 'ERROR'` (ERROR level also Force-syncs inside `Write-ConnectLog`).
2. Explicit `Sync-ConnectLogToServer -Force` before exit.
3. `Wait-ConnectExit -Reason 'unhandled' -Code 1` when connect-ui loaded; else `Read-Host` + `exit 1`.

---

## 3. Log watermark — PASS

**File:** `scripts/client/connect-ui.ps1` `Sync-ConnectLogToServer`

- `$appendOk` set only after successful scp **and** remote `cat … >> daylog` (`exit $ec`).
- `Write-ConnectLogSyncWatermark` / `$script:ConnectLogSyncOffset` update only inside `if ($appendOk)`.
- Failed append → WARN `LOG_SYNC_FAIL`; local bytes kept; watermark unchanged.

`connect-update.ps1` ship path likewise advances `.sync-offset` only when `$rCat.Ok`.

---

## 4. Designer forks — PASS

**File:** `scripts/client/users/designer/connect.ps1`

| Sub-item | Evidence |
|----------|----------|
| Persian quit / keys `useVk` | Session + drop + post-menu: VK only when KeyChar null/control; Q/Enter explicit; Persian printable ignored in idle loop |
| `ClearActiveMount` | All disconnect/quit paths: `Push-ServerConnectConf -ClearActiveMount` (not `-ActiveMount ''`, which left ACTIVE_MOUNT via `ActiveProjectId`) |
| Mutex | Prefer `Enter-ConnectSingleInstance` when `connect-ui` present; **inline** `Enter-DesignerSingleInstance` / `Exit-DesignerSingleInstance` so published designer ZIP (no connect-ui) still single-instances |

**This pass change:** mutex no longer no-ops when `connect-ui.ps1` is missing.

---

## 5. connect-update — PASS

**File:** `scripts/client/windows/connect-update.ps1`

- Header documents exit `1` = update failed (ERROR).
- ERROR paths (`ssh_missing`, `download_failed`, `incomplete_files`, checksum fail, `apply_rollback`, …) all `exit 1`.
- Apply is staged to `.client-update-new` then `Swap-LiveDir` with `.client-update-bak`; swap failure → `Restore-FromBak` + `apply_rollback` + `exit 1` (no partial live tree).
- Incomplete staging before swap deletes staging/new/bak and `exit 1` without touching live dirs.

---

## Untouched (per instructions)

- `git-mode.ps1` `banner_miss_tcp_open_budget` / Ensure `action=reseed` — left as-is.
- No `claude-server` / client deploy.

---

## Verdict

All five Win P1 items **PASS**. Only code change this pass: designer mutex fallback for packages without `connect-ui.ps1`.
