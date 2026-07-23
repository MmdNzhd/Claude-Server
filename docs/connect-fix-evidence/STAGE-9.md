# STAGE-9 Evidence Pack

## ID
- Stage: 9 (LOG_SYNC forbid shrink — never REBUILD when local < remote_was)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T20:10Z approx
- deploy_ran=no

## VERIFY
- Pre-fix: `Test-ConnectRemoteLogNeedsRebuild` / `test_connect_remote_log_needs_rebuild` returned true when remote > local (offset 0, 2x, or +1MB), triggering `LOG_SYNC_REBUILD` that replaced remote with smaller local (data loss).
- Pre-fix: Sync outer `catch { }` swallowed exceptions with no `LOG_SYNC_FAIL` breadcrumb; Mac had zero `LOG_SYNC_FAIL` lines.

## RESEARCH
1. https://man7.org/linux/man-pages/man1/rsync.1.html — never overwrite remote with older/smaller source without explicit intent (`--update` mindset).
2. https://pubs.opengroup.org/onlinepubs/9699919799/utilities/dd.html — append/offset copy preserves existing remote bytes.
3. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally — empty catch hides failures; surface durable detail.

What this changes:
- NeedsRebuild returns false when `local < remote` (forbid shrink); prior bloated-remote triggers disabled.
- `LOG_SYNC_SKIP reason=forbid_shrink` then append/merge only.
- Win: `LOG_SYNC_FAIL … detail=` including outer `detail=exception`.
- Mac: `_connect_log_sync_fail` + scp fail path.

What we will NOT do:
- Deploy/publish; destructive remote truncate when local is smaller.

## RED_TEST
```
Pre-patch: NeedsRebuild true when remote>local → LOG_SYNC_REBUILD replace.
Pre-patch: Mac LOG_SYNC_FAIL count=0; Win outer catch empty.
```

## IMPLEMENT
- `scripts/client/connect-ui.ps1`
- `scripts/client/connect-ui.sh`
- `scripts/client/tests/test-log-sync-forbid-shrink.ps1` (new)
- `scripts/client/tests/test-log-sync-contracts.ps1` (+c14/c15)
- `scripts/client/tests/run-all.ps1` (register)
- drive_by=none

## GREEN_TEST
```
test-log-sync-forbid-shrink.ps1 → 8 passed
test-log-sync-contracts.ps1 → 15 passed
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `client_scripts_repo_only` reason=`connect-ui.* updated in repo; no client publish/deploy this stage`

## GATE
`STAGE_9_DONE` 2026-07-22T20:10Z `deploy_ran=no` N+1 unlocked (Stage 11; Stage 10 already completed before 6d)
