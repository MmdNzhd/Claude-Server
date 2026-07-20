# TEST-AGENT-AUTH — Hard test (Agent D)

**Date:** 2026-07-20  
**Project:** `-p claude-code-server`  
**Deploy:** none  
**Verdict:** **PASS**

## Runtime tests

| Test | Command | Result |
|------|---------|--------|
| cursor-auth merge | `test-cursor-auth-merge.ps1` | **PASS** (exit 0) — all asserts including SQLite merge, no kill/WAL delete, golden sync, machineid heal, connect recovery |
| editor launch strategies | `test-editor-launch-strategies.ps1` | **PASS** (exit 0) — all asserts including 4 Cursor strategies, isolated profile, no force-kill on launch/retry |

## Static hard checks (`laptop-exec rg`)

### 1. Bare `Remove-Item $tmp` without `Remove-CursorAuthTempDir` (directories)

**Requirement:** Directory temp trees must be cleaned via `Remove-CursorAuthTempDir`, not bare `Remove-Item $tmp`.

| Location | What `$tmp` is | Cleanup | OK? |
|----------|----------------|---------|-----|
| L403–419 `Get-RemoteCursorAuthFromGolden` | Directory under `Get-CursorAuthTempRoot` (`cursor-golden-{guid}`) | `Remove-CursorAuthTempDir -Path $tmp` | **PASS** |
| L468–510 `Merge-CursorStorageJsonFromGolden` | **File** `$LocalPath.merge-src` (scp of `storage.json`) | bare `Remove-Item $tmp` (file, no `-Recurse`) | **PASS** (not a directory; check N/A) |

Helpers present:

- `Get-CursorAuthTempRoot` @ L366
- `Remove-CursorAuthTempDir` @ L388 (try/catch; never aborts disconnect)

**TEMP safety (directories): PASS** — no bare directory `Remove-Item $tmp`.

### 2. `golden-synced-at` / rotation checks

| Signal | Present? |
|--------|----------|
| `golden-synced-at.txt` in `cursor-auth-laptop.ps1` | **YES** L623, L656–658 |
| Rotation comment + stamp vs `exported-at` | **YES** L652–657 (`rotation invalidates…`; `$syncedAt -eq $goldenExportedAt`) |
| Also stamped from Mac path (`git-mode.sh`) | **YES** |

**PASS**

### 3. AA616 / `Get-CursorAuthTempRoot`

| Signal | Present? |
|--------|----------|
| `Get-CursorAuthTempRoot` | **YES** L366–386 (long-path TEMP; documents broken 8.3 shorts) |
| Literal string `AA616` in tree | **NO** (rg exit 1 across repo) |

**PASS** on implementation (`Get-CursorAuthTempRoot` + safe dir remove). Note: ticket id `AA616` is not embedded as a comment/string.

## HARD FAIL gates

| Gate | Status |
|------|--------|
| Runtime test failure | not triggered |
| Missing directory TEMP safety | not triggered |
| Missing golden-synced-at / rotation | not triggered |
| Missing Get-CursorAuthTempRoot | not triggered |

## Summary

Agent D hard test **PASS**. Both PowerShell suites green; directory TEMP cleanup uses `Remove-CursorAuthTempDir`; golden sync stamp + token rotation logic present; `Get-CursorAuthTempRoot` present.
