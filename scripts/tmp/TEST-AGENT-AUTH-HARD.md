# TEST-AGENT-AUTH-HARD — Wave2 Agent R

**Date:** 2026-07-20  
**Project:** `-p claude-code-server` (laptop-exec only)  
**Deploy:** none  
**Verdict:** **HARD FAIL**

## Runtime tests

| Test | Command | Result |
|------|---------|--------|
| cursor-auth merge (Win) | `scripts/client/tests/test-cursor-auth-merge.ps1` | **PASS** (exit 0) — SQLite merge, no kill/WAL delete, golden sync, machineid heal, connect recovery |
| cursor-auth merge (Mac/sh) | `scripts/client/tests/test-cursor-auth-merge.sh` | **HARD FAIL** (exit 1) — `merge_cursor_auth_into_local_db failed` because `cursor_sqlite3_available` / `sqlite3` missing on WSL2 runner (`command -v sqlite3` → none). Static grep asserts (no python3 pipe pattern) passed before the functional merge. |
| editor launch | `scripts/client/tests/test-editor-launch.ps1` | **PASS** (exit 0) — code/cursor on PATH; Launch-RemoteEditor + strategies + snapshot helpers defined |
| editor launch strategies | `scripts/client/tests/test-editor-launch-strategies.ps1` | **PASS** (exit 0) — URI format, 4 Cursor strategies, isolated profile, no force-kill on launch/retry |

## Contract script

`scripts/tmp/test-auth-temp-contracts.ps1` — **PASS** (exit 0), 8/8:

| Contract | Result |
|----------|--------|
| `Get-CursorAuthTempRoot` exists | PASS |
| `Remove-CursorAuthTempDir` exists | PASS |
| `Get-RemoteCursorAuthFromGolden` finally calls `Remove-CursorAuthTempDir` (not bare `Remove-Item -Recurse $tmp`) | PASS |
| No `Remove-Item $tmp -Recurse` in `cursor-auth-laptop.ps1` | PASS |
| File merge-src `Remove-Item $tmp -Force` allowed (2 hits) | PASS |
| `golden-synced-at` + rotation (`exported-at` / `$syncedAt -eq $goldenExportedAt`) on Win skip path | PASS |
| Win skip-already-complete path present | PASS |

## HARD FAIL gates

| Gate | Status |
|------|--------|
| `test-cursor-auth-merge.ps1` failure | not triggered |
| `test-cursor-auth-merge.sh` failure | **TRIGGERED** — sqlite3 absent on WSL2; merge functional step failed |
| `test-editor-launch.ps1` failure | not triggered |
| `test-editor-launch-strategies.ps1` failure | not triggered |
| Auth TEMP contracts failure | not triggered |

## Root cause (merge.sh)

Runner is WSL2 (`Linux DESKTOP-DTCC6CD … microsoft-standard-WSL2`). `merge_cursor_auth_into_local_db` requires `sqlite3` CLI; `cursor_sqlite3_available` returned 1 → test exited with `FAIL: merge_cursor_auth_into_local_db failed`.

## Summary

Wave2 Agent R **HARD FAIL**. Win merge + editor launch suites and auth-TEMP contracts are green; Mac/sh merge test failed on missing `sqlite3` in the WSL environment used by `laptop-exec run … bash`.
