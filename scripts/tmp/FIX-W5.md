# FIX-W5 — Mount + Update + Security leftovers

Date: 2026-07-20  
Project: `claude-code-server` via laptop-exec only. **No deploy. No commit.**

## Summary

Closed remaining Mount/Update/Security leftovers from `BUGS-SERIOUS-20260720.md` (agents 1/2/6 track). Several items were already landed by prior agents; this pass restored Mac update (regressed by a later overwrite), hardened OAuth migrate on install, and closed CR-strip / relaunch gaps.

## Mount

| # | Slug | Status | Notes |
|---|------|--------|-------|
| 5 | `win-restore-deletes-git` | **OK (prior)** | `claude-mount.sh` `restore_try` / `_restore_git_body`: never `Remove-Item` on real `.git` dir; skip when Container+HEAD; Leaf worktree pointer only. |
| 6 | `watchdog-tunnel-down-no-git-restore` | **OK (prior)** | `claude-watchdog.sh` tunnel-DOWN calls `"$MOUNT_BIN" down` before raw umount. |
| 20 | `active-mount-first-conf-inference` | **OK (prior)** | Watchdog + automount: no first-alphabetical conf; LAST_ACTIVE / already-mounted only. |
| 68 | `mount-load-global-no-cr-strip` | **OK** | `_load_global` strips `\r` (prior). **This pass:** `claude-automount.sh` also strips `\r` when loading `TUNNEL_PORT` / `ACTIVE_MOUNT`. |

## Update

| # | Slug | Status | Notes |
|---|------|--------|-------|
| 9 | `update-exit0-on-error` | **OK** | Win+Mac ERROR paths `exit 1`. |
| 10 | `win-partial-apply-no-rollback` | **OK** | Stage → swap → rollback on fail; no `applied_ok` unless swap succeeds. |
| 28 | `non-atomic-live-copy-item` | **OK** | Win `Swap-LiveDir`; Mac `_swap_dir` / NEW_ROOT. |
| 29 | `copy-errors-swallowed` | **OK** | Tracked copy failures → exit 1 before swap. |
| 30 | `no-checksum-after-scp` | **OK** | Win `Test-BundleChecksums`; Mac `_verify_checksums` (skip if no `checksums.txt`). |
| 32 | `identityagent-gap-on-client-update` | **OK** | Win `SshCommonOpts` + scp; Mac `SSH_EXTRA_OPTS` (`IdentitiesOnly=yes`, `IdentityAgent=none`). |
| 33 | `mac-update-hang-no-process-timeout` | **OK** | Mac `_run_timed` wraps ssh/scp. |
| 34 | `publish-manifest-utf8-bom` | **OK (prior)** | `deploy-client-bundles.ps1` writes manifest/checksums via `UTF8Encoding($false)`. |
| 65 | `bat-unbounded-relaunch` | **OK** | `connect.bat` `CLAUDE_CONNECT_UPDATE_DEPTH` stop at ≥3. **This pass:** Mac `connect.sh` same bound (≥2 depth → continue). |

### Mac update regression note

`scripts/client/mac/connect-update.sh` had been overwritten back to an in-place `cp -f` path (no IdentityAgent / checksum / atomic swap). Restored full hardened script (367 lines) from the Agent-6 tree.

## Security

| # | Slug | Status | Notes |
|---|------|--------|-------|
| 1 | `hardcoded-sepidz-sudo-fallback` | **OK (prior)** | `Get-DeployCredentials.ps1` throws if local/env missing — no hardcoded password. |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | **OK (prior)** | `deploy-client-bundles.ps1` calls `Get-SepidzSudoPassword` / `Get-SmartSudoPassword` only. |
| 4 | `sqlserver-password-in-add-user-template` | **OK (prior)** | `add-user.sh` uses `CHANGE_ME`. `CLAUDE.md` example also `CHANGE_ME`. |
| 3 | `shared-oauth-in-etc-environment` | **OK** | Token store `/etc/claude-code/oauth.env` 0600. **This pass:** `install.sh` migrates legacy `/etc/environment` token via `write_env_token` (strips environment). |
| 18 | `cursor-golden-world-readable` | **OK (prior+)** | `install.sh` `chmod 600 /etc/cursor-auth/golden/*`; export also 0600. |

### Gitignore

`*-deploy.local.ps1` and `publish/*-deploy.local.ps1` are gitignored (covers `sepidz-deploy.local.ps1` / `smart-deploy.local.ps1`). Local password files must stay untracked — do not commit.

## Files touched (this agent)

- `scripts/client/mac/connect-update.sh` — restored full stage/checksum/IdentityAgent/atomic swap
- `scripts/client/mac/connect.sh` — bound update relaunch recursion
- `scripts/server/claude-automount.sh` — CR strip on connect conf load
- `scripts/server/commands/install.sh` — OAuth migrate from `/etc/environment` on install
- `scripts/tmp/FIX-W5.md` — this report

Already correct (no edit needed this pass): `claude-mount.sh`, `claude-watchdog.sh`, Win `connect-update.ps1`, `connect.bat`, `Get-DeployCredentials.ps1`, `deploy-client-bundles.ps1`, `add-user.sh`, `.gitignore`.

## Leftover risks

1. **Concurrent agent races** — Mac update / connect.sh were briefly regressed mid-session; re-verify before deploy.
2. **Checksum optional** — if bundle lacks `checksums.txt`, verify is skipped (WARN) rather than fail-closed.
3. **OAuth migrate** runs only when `/etc/environment` still has the token and `claude-auth-lib.py` is installed; fresh installs that never wrote environment are fine.
4. Out of W5 scope but still open elsewhere: mount #22/#24 (client banner / foreign ss), UX connect-design Persian keys.

## Verify (no deploy)

```bash
laptop-exec rg -p claude-code-server "IdentityAgent|_swap_dir|_verify_checksums" scripts/client/mac/connect-update.sh
laptop-exec rg -p claude-code-server "UPDATE_DEPTH" scripts/client/windows/connect.bat scripts/client/mac/connect.sh
laptop-exec rg -p claude-code-server "tr -d|PYMIG|chmod 600 /etc/cursor-auth" scripts/server/claude-automount.sh scripts/server/commands/install.sh
```
