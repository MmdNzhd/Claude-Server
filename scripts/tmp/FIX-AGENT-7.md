# FIX-AGENT-7 (Auth) — 2026-07-20

No deploy. No commit.

## Fixed slugs

| # | Slug | Fix |
|---|------|-----|
| 13 | `win-auth-skip-ignores-golden-rotation` | `Test-CursorAuthNeedsRefresh` adds `golden_stale` when `exported-at` ≠ `golden-synced-at.txt` (via SshX). Connect skip path already gates on `authNeedsRefresh`. |
| 14 | `mac-o-key-dead-when-sticky-opened` | Mac O handler gates on `!remote_editor_on_correct_folder` (`_on_folder_now`), not sticky `_editor_opened`. |
| 42 | `auth-relaunch-unused-when-already-on-folder` | Win: `$authRelaunch` after successful merge → `Launch-RemoteEditor -AuthRelaunch` even when already on folder (soft-stop profile). Mac: launch when `CURSOR_AUTH_RELAUNCH=1` even if `_editor_opened=1`. |
| 43 | `mac-auth-relaunch-on-skipped-failure` | `skipped` case no longer exports `CURSOR_AUTH_RELAUNCH=1`. |
| 44 | `win-code-no-isolated-profile` | `Get-CodeRemoteProfileDir` → `%LOCALAPPDATA%\ClaudeServerCodeProfile`; launch strategies + process match use `--user-data-dir`. |
| 45 | `win-needs-refresh-misses-machineid-file` | `Test-CursorAuthNeedsRefresh` compares profile `machineid` to golden → `machineid_file_mismatch`. |
| 46 | `win-build-auth-early-path-drops-auth-json-metadata` | Early `Build-CursorAuthValuesFromGoldenDir` path keeps `cachedEmail` / signup / stripe fields from `auth.json`. |
| 66 | `mac-agent-home-false-positive-vs-win` | Mac `remote_editor_in_agent_home` = URI-less only (match Win); removed agent_home soft-kill (prefer `--new-window`). |
| + | bare `Remove-Item $tmp` / AA616~1.TAV | All auth temps via `Get-CursorAuthTempRoot` + `Remove-CursorAuthTempDir` (storage merge + machineid heal). |

## Files touched

- `scripts/client/cursor-auth-laptop.ps1`
- `scripts/client/editor-launch.ps1`
- `scripts/client/editor-launch.sh`
- `scripts/client/windows/connect.ps1`
- `scripts/client/mac/connect.sh`
- `scripts/client/tests/test-cursor-auth-merge.ps1`
- `scripts/client/tests/test-editor-launch-strategies.ps1`

## Tests

- `test-cursor-auth-merge.ps1` — PASS
- `test-editor-launch-strategies.ps1` — PASS

## Leftover risks

- Auth relaunch soft-stops **all** ClaudeServerCursorProfile windows (same as Mac AUTH_RELAUNCH) — multi-project users may lose other open remotes briefly.
- `Test-CursorAuthNeedsRefresh` adds SshX calls for golden stamp + machineid (latency on every connect auth decision).
- Win VS Code disconnect still uses `Stop-RemoteEditor` path matching; no separate force-kill of entire Code profile tree beyond URI/path match.
- Concurrent agents may race on shared files; re-verify markers if another agent rewrites connect/auth.

## AUTH ERROR logs

`Write-AuthSyncLog "AUTH ERROR …"` on `golden_stale` and `machineid_file_mismatch` (and check failures).
