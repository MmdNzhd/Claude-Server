# TEST-AGENT-SECURITY-HARD (wave2 Agent O)

Static security HARD suite. **No deploy.**  
Runner: `scripts/tmp/test-security-contracts.ps1`  
Command: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tmp/test-security-contracts.ps1`  
Project: `-p claude-code-server` (laptop-exec only)

## Overall

**HARD FAIL** (1 FAIL / 6 checks) — suite exit code **1**

## Contract checks

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | `publish/Get-DeployCredentials.ps1` / `deploy-client-bundles.ps1` — no hardcoded password and no `sepidz@Admin` fallback when local file missing | **PASS** | Credentials helpers **throw** when password absent (`No hardcoded fallback is allowed`). No `sepidz@Admin` in either committed script. Bundles call `Get-SepidzSudoPassword` / `Get-SmartSudoPassword` only. |
| 2 | `add-user.sh` settings.json template — no real SQL password (placeholder OK) | **PASS** | `"SQLSERVER_PASSWORD": "CHANGE_ME"` |
| 3 | Install/update scripts write `CLAUDE_CODE_OAUTH_TOKEN` into `/etc/environment` world-readable without `chmod 600` | **PASS** | `update-server.sh` writes `/etc/claude-code/oauth.env` then `chmod 600`; strips token from `/etc/environment`. `deploy-auth` uses `claude-auth-lib.py` (root-only file). No unprotected append of live token to `/etc/environment`. |
| 4 | Golden `auth.json` installed mode **644** in scripts | **PASS** | `cursor-auth-export.sh`: `chmod 700` on golden dir, `chmod 600` on `golden/*` (not 644). |
| 5 | Sudo password echoed on cmdline in client scripts | **FAIL** | `scripts/client/git-mode.sh` `laptop_ssh_bootstrap_local`: builds SSH_ASKPASS script via `printf 'echo '` + `printf '%q' "$LAPTOP_ADMIN_PW"` — when askpass runs, password appears on the `echo` process cmdline. |
| 6 | `install-client-bundle.sh` grants NOPASSWD / merges ALL users' keys into sepidz without restriction | **PASS** | Unrestricted `_sync_sepidz_update_keys` / `for d in /home/*` merge **removed** (comment: do NOT merge). `sudoers.d/claude-client-deploy` grants **smart** NOPASSWD for bundle install only; **sepidz** has no NOPASSWD. |

## Suite machine output

```
[PASS] CHECK 1: deploy credentials no hardcoded/sepidz@Admin fallback
[PASS] CHECK 2: add-user.sh SQL password placeholder only - placeholder OK: CHANGE_ME
[PASS] CHECK 3: OAUTH token not world-readable /etc/environment
[PASS] CHECK 4: golden auth.json not mode 644
[FAIL] CHECK 5: client scripts no sudo password on cmdline - scripts\client\git-mode.sh askpass embeds password in echo cmdline
[PASS] CHECK 6: no unrestricted sepidz key merge/NOPASSWD for all keys
Overall: HARD FAIL (1 FAIL / 6 checks)
```

## rg / secrets scan (`publish/` + `scripts/server/commands/`)

Patterns: `sepidz@Admin`, `Mohammad123`, `*SudoPassword='...'`, `SQLSERVER_PASSWORD`, `CLAUDE_CODE_OAUTH_TOKEN=`, private-key headers, live `sk-ant-oat01-…` literals.

### Notable hits

| Path | Finding | Notes |
|------|---------|--------|
| `publish/sepidz-deploy.local.ps1` | Real `$SepidzSudoPassword` | Expected **gitignored** local deploy secret; not a check-1 failure (loader does not hardcode fallback). |
| `publish/smart-deploy.local.ps1` | Real `$SmartSudoPassword` | Same — gitignored local. |
| `publish/*-deploy.local.ps1.example` | Placeholder passwords | OK. |
| `publish/Get-DeployCredentials.ps1` | Docs show `$…SudoPassword = '...'` in throw messages | Not a live password. |
| `scripts/server/commands/add-user.sh` | `SQLSERVER_PASSWORD`: `CHANGE_ME` | Placeholder — check 2 PASS. |
| `scripts/server/commands/update-server.sh` | Writes token to `/etc/claude-code/oauth.env` + `chmod 600`; strips `/etc/environment` | Secure path — check 3 PASS. |
| `scripts/server/commands/diagnose-auth.sh` / `sync-auth.sh` / `verify.sh` / `install.sh` | Grep/read of `CLAUDE_CODE_OAUTH_TOKEN=` | No hardcoded token literals. |

### No hits (in scope)

- Live `sk-ant-oat01-…` token strings in `publish/` or `commands/`
- `BEGIN … PRIVATE KEY` blocks
- `Mohammad123` in `commands/add-user.sh` (docs/`CLAUDE.md` may still mention it outside this scan scope)

## Residual risk (out of contract but observed)

- Many `scripts/tmp/*` helpers still embed plaintext `sepidz@Admin` in SSH/`sudo -S` one-liners (not in this HARD contract path list).
- Check **5** is the sole HARD failure: Mac askpass embeds admin password into an `echo` argv.

## Artifacts

- Suite: `scripts/tmp/test-security-contracts.ps1`
- Report: `scripts/tmp/TEST-AGENT-SECURITY-HARD.md`
- Aux scan: `scripts/tmp/rg-secrets-scan.ps1`
