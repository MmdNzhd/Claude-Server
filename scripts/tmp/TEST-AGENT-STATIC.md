# Agent F — Static regression matrix (P0/P1)

**Project:** `claude-code-server`  
**Tooling:** `laptop-exec rg/read` only (`-p claude-code-server`)  
**Date:** 2026-07-20  

**Legend:** HIT = pattern still present (broken) · CLEAN = not found / fixed path  

| slug | pri | status | evidence path |
|------|-----|--------|---------------|
| sepidz@Admin / hardcoded sudo password fallbacks in publish/ | P0 | HIT | `publish/Get-DeployCredentials.ps1` — `Get-SepidzSudoPassword` returns `'sepidz@Admin'` when env/local file empty |
| CLAUDE_CODE_OAUTH_TOKEN write to /etc/environment without 600 | P0 | HIT | `scripts/server/claude-auth-lib.py` `write_env_token` — `ENV_FILE.write_text(...)` with no `os.chmod(..., 0o600)`; profile gets `0o644` only. Also `scripts/server/commands/update-server.sh` appends token to `/etc/environment` without chmod 600 |
| SQL password literals in add-user.sh settings template | P0 | HIT | `scripts/server/commands/add-user.sh:175` — `"SQLSERVER_PASSWORD": "Mohammad123"` |
| Remove-Item.*\.git in restore_try / restore paths | P0 | HIT | `scripts/server/claude-mount.sh:220` — `restore_try` contains `if (Test-Path $p/.git) { Remove-Item $p/.git -Force ... }` before Rename-Item |
| active mount first alphabetical inference | P1 | HIT | `scripts/server/claude-automount.sh:108-116` — `for _c in "$CONF_DIR"/*.conf` then `ACTIVE_MOUNT="$_id"; break` (bash glob = lexical first) |
| banner_miss_tcp_open return $true without SoftFail budget DROP | P1 | HIT | `scripts/client/git-mode.ps1` ENSURE_TUNNEL ~875–878: `reason=banner_miss_tcp_open` then `return $true` (no SoftFailCount / TUNNEL_DROP). TUNNEL_SYNC banner_miss (~506–508) resets SoftFailCount and stays healthy |
| EditorSeenOpen forcing editorOpened | P1 | HIT | `scripts/client/windows/connect.ps1:1504-1505`, `:1558-1559`, `:1731` — `elseif ($script:EditorSeenOpen) { $editorOpened = $true }` |
| SoftFailCount -lt 6 without hard fail branch after | P1 | HIT | `scripts/client/git-mode.ps1:484-488` — if SoftFailCount -lt 6 return $true; when count ≥6 no `else` / TUNNEL_DROP / return $false; falls through to later Test-TunnelUp which may still return $true |
| `; true` after cat >> log | P1 | HIT | `scripts/client/connect-ui.ps1:227` — `cat ... >> ...; ...; true`; `scripts/client/windows/connect-update.ps1:416` — same; `scripts/client/connect-ui.sh:269` |
| ReadAllBytes on full day log | P1 | HIT | `scripts/client/connect-ui.ps1:191` — `$all = [System.IO.File]::ReadAllBytes($script:ConnectLogPath)`; `scripts/client/windows/connect-update.ps1:397` — same on `$dayLog` (chunking only after full-file load) |
| exit 0 after update ERROR | P1 | HIT | `scripts/client/windows/connect-update.ps1:236-237,299,302,308-310,371-372` — `Write-UpdateFileLog ... 'ERROR'; exit 0` |
| applied_ok despite failed copies | P1 | CLEAN | `scripts/client/windows/connect-update.ps1:368-376` — `$failed.Count -gt 0` logs ERROR and `exit 0` before `applied_ok`; applied_ok only on success path |
| KeyChar.*Q / always useVk in designer connect forks | P1 | HIT | `scripts/client/users/designer/connect.ps1:543-544,554` — always ORs `$ki.Key -eq [ConsoleKey]::R/G` with KeyChar (no `useVk` gate); unlike main `connect.ps1` which gates VK on null/control KeyChar |

## Verdict

**HARD FAIL** — P0 still HIT: sudo fallback `sepidz@Admin`, OAuth `/etc/environment` without mode 600, SQL password literal in `add-user.sh`, and dangerous `Remove-Item $p/.git` in `restore_try`.

| pri | HIT | CLEAN |
|-----|-----|-------|
| P0 | 4 | 0 |
| P1 | 8 | 1 |
| **total** | **12** | **1** |
