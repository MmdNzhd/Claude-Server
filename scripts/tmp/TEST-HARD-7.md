# HARD TEST 7 — Cursor Auth Merge & Editor Launch

**Project:** `claude-code-server`  
**Date:** 2026-07-20 (UTC)  
**Method:** `laptop-exec -p claude-code-server` only (no deploy)

---

## OVERALL: **FAIL**

One regression in `test-cursor-auth-merge.ps1`. Editor-launch tests pass. Static auth-temp / refresh-gate checks pass.

---

## Runtime Tests

| Script | Exit | Result |
|--------|------|--------|
| `scripts/client/tests/test-cursor-auth-merge.ps1` | **1** | **FAIL** — 32 PASS, 1 FAIL |
| `scripts/client/tests/test-editor-launch-strategies.ps1` | 0 | PASS — 41/41 |
| `scripts/client/tests/test-editor-launch.ps1` | 0 | PASS — 5/5 |

### test-cursor-auth-merge.ps1 — failure detail

| Status | Assertion |
|--------|-----------|
| **FAIL** | `Mac relaunches when AUTH_RELAUNCH set` |
| PASS | All other 32 assertions (SQLite merge, no kill/close, Get-CursorAuthTempRoot, golden_stale, machineid drift, Windows auth-relaunch, etc.) |

**Root cause:** `scripts/client/mac/connect.sh` exports `CURSOR_AUTH_RELAUNCH=1` after successful auth sync (lines ~845, ~851) but never emits the expected step message or explicit relaunch block:

```
Reloading $EDITOR_NAME (auth refresh)
```

Windows parity exists in `scripts/client/windows/connect.ps1` (~1497):

```powershell
Step "Reloading $EditorName (auth refresh)"
```

Mac only opens the editor when `_editor_opened -eq 0`; it does not relaunch when auth refresh succeeds and the editor is already on-folder. `editor-launch.sh` handles `CURSOR_AUTH_RELAUNCH` soft-stop inside `launch_remote_editor`, but Mac `connect.sh` never calls launch with that flag when `_editor_opened=1` and `_on_folder=1`.

---

## Static Analysis

### Get-CursorAuthTempRoot / Remove-CursorAuthTempDir

| File | Status |
|------|--------|
| `scripts/client/cursor-auth-laptop.ps1` | **PASS** — both functions defined; all auth temp dirs use `Join-Path (Get-CursorAuthTempRoot) …` and cleanup via `Remove-CursorAuthTempDir -Path` |

`Remove-CursorAuthTempDir` wraps `Remove-Item -LiteralPath $Path -Recurse -Force` in try/catch (never aborts connect).

### No bare `Remove-Item $tmp -Recurse` for auth temp

| Scope | Status |
|-------|--------|
| `cursor-auth-laptop.ps1` | **PASS** — no `Remove-Item $tmp`; test regex `Remove-Item \$tmp` absent |
| `git-mode.sh` (Mac auth) | **PASS** — no bare `$tmp` Remove-Item |
| `mac/connect.sh` | **PASS** — no auth temp cleanup |

Unrelated `$tmp` Remove-Item usage exists only in test scaffolding (`test-connect-update-*.ps1`) and connect-update staging — not auth temp paths.

### golden_stale / machineid refresh gates

| Location | Status |
|----------|--------|
| `cursor-auth-laptop.ps1` → `Test-CursorAuthNeedsRefresh` | **PASS** — `machineid_file_mismatch`, `golden_stale`, `serviceMachineId_empty` |
| `git-mode.sh` → `cursor_auth_needs_refresh` | **PASS** — `machineid_file_mismatch`, `golden_stale`, `serviceMachineId_empty` |
| Mac skip path heals machineid | **PASS** — `write_cursor_profile_machineid` on already-complete skip |

---

## Summary

| Area | Result |
|------|--------|
| Auth merge invariants (Windows + shared PS) | PASS |
| Editor launch strategies | PASS |
| Editor launch self-test | PASS |
| Mac auth-relaunch parity | **FAIL** |
| Auth temp dir safety | PASS |
| Refresh gate static checks | PASS |

**Fix needed (not applied):** Add Mac `connect.sh` block equivalent to Windows — when `CURSOR_AUTH_RELAUNCH=1` and editor already on folder, `step "Reloading $EDITOR_NAME (auth refresh)"` and call `launch_remote_editor` so Electron reloads tokens/machineid.
