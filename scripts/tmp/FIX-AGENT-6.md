# FIX-AGENT-6 — Update/apply hardening

Date: 2026-07-20  
Scope: bugs 9,10,28,29,30,31,32,33,34,40,65  
Deploy/publish to live servers: **not done** (code + tests only). Commit: **not done**.

## Fixed slugs

| # | Slug | Fix |
|---|------|-----|
| 9 | `update-exit0-on-error` | Win/Mac update ERROR paths exit **1** (not 0). Soft skips (unreachable / up-to-date) still exit 0. |
| 10 | `win-partial-apply-no-rollback` | Apply builds a new tree under `.client-update-new`, swaps live dirs; on swap failure restores from `.client-update-bak`. |
| 28 | `non-atomic-live-copy-item` | No in-place live `Copy-Item`/`cp`; stage then `Move-Item`/`mv` swap. |
| 29 | `copy-errors-swallowed` | `Copy-Tracked` / copy failures append to `$failed` / `failed=1`; never `applied_ok` if any fail. |
| 30 | `no-checksum-after-scp` | Deploy/publish write `checksums.txt`; clients verify SHA-256 after download (skip+WARN if missing for old bundles). |
| 31 | `deploy-client-bundle-rm-live` | `deploy-client-bundle.sh` (+ `install-client-bundle.sh`) stage then rename-swap; no `rm -rf` of live share mid-download. |
| 32 | `identityagent-gap-on-client-update` | Client update ssh/scp use `IdentitiesOnly=yes` + `IdentityAgent=none` (parity with deploy). |
| 33 | `mac-update-hang-no-process-timeout` | Mac `_run_timed` kills hung ssh (20s) / scp (180s). |
| 34 | `publish-manifest-utf8-bom` | `publish/deploy-client-bundles.ps1` writes manifest via `UTF8Encoding($false)` (no BOM). |
| 40 | `update-server-exit0-on-verify-fail` | `update-server.sh` tracks `VERIFY_OK` and exits 1 if verify fails. |
| 65 | `bat-unbounded-relaunch` | `connect.bat` + Mac `connect.sh` bound update relaunch via `CLAUDE_CONNECT_UPDATE_DEPTH` (max 3 / depth≥2). |

## Files touched

- `scripts/client/windows/connect-update.ps1`
- `scripts/client/mac/connect-update.sh`
- `scripts/client/windows/connect.bat`
- `scripts/client/mac/connect.sh` (relaunch depth only)
- `scripts/server/commands/deploy-client-bundle.sh`
- `scripts/server/commands/install-client-bundle.sh`
- `scripts/server/commands/update-server.sh`
- `publish/deploy-client-bundles.ps1`
- `scripts/client/tests/test-connect-update-hardening.ps1` (new)
- `scripts/client/tests/test-client-auto-update.sh` (extra asserts)

## Verification

- `test-connect-update-hardening.ps1`: **27/27 PASS**
- `test-client-auto-update.sh`: **25/25 PASS**
- `bash -n` / PowerShell parse: OK on touched scripts

## Leftover risks

- Checksum verify is **WARN-skip** when `checksums.txt` is absent (pre-redeploy servers). Full protection needs a future `deploy-client-bundle` / publish on each site (not run by this agent).
- Directory swap on Windows is rename-based, not a single filesystem transaction across `windows/`+`mac/`; mac swap failure rolls windows back, but a crash mid-swap can still leave bak dirs (`.client-update-bak`).
- Concurrent agents may race on shared Mac/Win files; re-verified markers after writes.
- Agent 10 owns deeper update fail-exit e2e (`#64`); this agent added static contracts only.
