# Fix Agent 1 (Security) — 2026-07-20

Scope: bugs **1, 2, 3, 4, 16, 17, 18, 19, 54, 74**. No deploy/publish. No commit.

## Results

| # | Slug | Status | Notes |
|---|------|--------|-------|
| 1 | `hardcoded-sepidz-sudo-fallback` | **FIXED** | `publish/Get-DeployCredentials.ps1` — `Get-SepidzSudoPassword` / `Get-SmartSudoPassword` throw if env + `*-deploy.local.ps1` missing; removed `return 'sepidz@Admin'`. |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | **FIXED** | `publish/deploy-client-bundles.ps1` — removed `if (-not $sudoPw) { $sudoPw = 'sepidz@Admin' }`; relies on Get-SepidzSudoPassword throw. |
| 2 | `sepidz-ak-merge-plus-nopasswd-bundle` | **FIXED** | Stopped merging developer keys into sepidz `authorized_keys` in `deploy-client-bundle.sh`, `install-client-bundle.sh`, `add-user.sh`. Narrowed `scripts/server/sudoers.d/claude-client-deploy` — **removed `sepidz` NOPASSWD**; Smart-only. Sepidz deploy uses `sudo -S` + local password file. |
| 3 | `shared-oauth-in-etc-environment` | **FIXED** | Token store → `/etc/claude-code/oauth.env` mode **0600** via `claude-auth-lib.py` (`write_env_token` strips legacy `/etc/environment`). Profile.d is a non-secret stub. Updated sync/verify/diagnose/install/update-server/deploy-auth + CLAUDE.md. |
| 4 | `sqlserver-password-in-add-user-template` | **FIXED** | `add-user.sh` template `SQLSERVER_PASSWORD` → `CHANGE_ME`; CLAUDE.md docs updated. |
| 16 | `always-elevated-connect` | **FIXED** | `scripts/client/windows/connect.ps1` — removed always-RunAs block; elevate only via `Invoke-LaptopAdminOps` / `-AdminFix`. (Shared file with Tunnel-Win — re-applied after conflict.) |
| 17 | `administrators-authorized-keys-server-key` | **FIXED** | Kept `from=127.0.0.1,::1,localhost,…` only; comment forbids broadening; admin AK writes gated on `Test-IsAdmin`. |
| 18 | `cursor-golden-world-readable` | **FIXED** | Golden dir **0700**, files **0600** in `cursor-auth-lib.py`, `cursor-auth-export.sh`, `import-cursor-golden-laptop.sh`, `install.sh`. Root sync/cron/add-user still push per-user copies. |
| 19 | `secrets-adjacent-logging` | **FIXED** | Auth fingerprints no longer include token prefix bytes; `/var/log/claude-auth.log` → **0600**; `sudo-from-laptop` no longer embeds sudo password in remote argv; Mac `git-mode.sh` diagnose no longer fetches `claude_laptop` private key. |
| 54 | `world-readable-client-bundle-server-tree` | **FIXED** | `deploy-client-bundle.sh` + `install-client-bundle.sh` **remove `server/`** from `/usr/local/share/claude-client/` after packaging (clients already skip `server/*` on apply). |

## Files touched (Agent 1)

- `publish/Get-DeployCredentials.ps1` (new/untracked)
- `publish/deploy-client-bundles.ps1` (new/untracked)
- `scripts/server/sudoers.d/claude-client-deploy` (new/untracked)
- `scripts/server/commands/install-client-bundle.sh` (new/untracked)
- `scripts/server/sudo-from-laptop.sh` (new/untracked)
- `scripts/server/commands/deploy-client-bundle.sh`
- `scripts/server/commands/add-user.sh`
- `scripts/server/claude-auth-lib.py`
- `scripts/server/claude-auth-sync.sh`
- `scripts/server/commands/{deploy-auth,sync-auth,verify,diagnose-auth,install,update-server,import-cursor-golden-laptop}.sh`
- `scripts/server/cursor-auth-lib.py`
- `scripts/server/cursor-auth-export.sh`
- `scripts/server/CURSOR-AUTH-PILOT.md`
- `scripts/client/windows/connect.ps1` (shared w/ Agent 3)
- `scripts/client/git-mode.sh` (shared w/ Agent 4)
- `CLAUDE.md`

## Leftover risks

1. **Existing live Sepidz hosts** may still have merged developer keys in `sepidz` `authorized_keys` and/or old sudoers with sepidz NOPASSWD until next `claude-server install` (explicitly not deployed this run).
2. **Existing `/etc/environment` tokens** remain until `sudo claude-server deploy-auth <token>` migrates them.
3. **Existing golden files** stay 644 until next export/sync chmod path runs.
4. **User-login `cursor-auth-sync` / `claude-auth-sync`** can no longer read root-only stores; rely on root `add-user` / cron / `sync-*-auth` (automount already timeout-fails open).
5. **Legacy packages** that hardcode `sepidz@IP` for update without the user's own key will fail until clients use `REMOTE_USER` (already preferred in connect-update).
6. **`docs/superpowers/plans/...`** still mentions writing token to `/etc/environment` (stale plan doc; not load-bearing).

## Verification

- `bash -n` on edited shell scripts: OK
- `rg sepidz@Admin|Mohammad123` in publish/server/CLAUDE.md: none
- `laptop-exec git -p claude-code-server -- diff --stat` (Agent-1 paths): see session output
