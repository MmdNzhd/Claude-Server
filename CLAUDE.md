# Claude Code Server Ã¢â‚¬â€ Project Rules

## Language Rule

**No Persian text anywhere in the repo** (scripts, docs, skills, plans, READMEs). English only Ã¢â‚¬â€ comments, docs, variable names, error messages, skill triggers. Keyboard-layout notes may say "Persian/Arabic layout" in English prose.

## Architecture Overview

SSH reverse tunnel: client laptop Ã¢â€ â€™ server, port = `20000 + (server_UID - 1000) * 10 + slot` (10-port non-overlapping block per user, slot 0-9; see `Get-TunnelPortUserBase` / `tunnel_port_user_base`).
**Source of truth = laptop disk.** Optional SSHFS under `~/mounts/<ID>/` is for Cursor UI only and may be STALE or NOT_MOUNTED.

**Agents must use SSH-first `laptop-exec`** (not Cursor Read/Grep/Write on `/mounts/`). Connect UI `sshx()` / `SshX()` open one-shot SSH (no mux). `laptop-exec` uses a shared SSH ControlMaster through the same reverse tunnel.

```
Laptop Ã¢â€â‚¬Ã¢â€â‚¬SSHÃ¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¶ Server (port 22) + reverse tunnel (20000+UID)
Cursor agent on server Ã¢â€â‚¬Ã¢â€â‚¬laptop-exec (ControlMaster)Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¶ 127.0.0.1:TUNNEL_PORT Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¶ laptop disk
Optional: Server Ã¢â€â‚¬Ã¢â€â‚¬SSHFSÃ¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¶ Laptop (UI; may be stale Ã¢â‚¬â€ never prefer over laptop-exec)
```

## File Map

```
scripts/
  client/
    mac/connect.sh                # Mac launcher (bash, runs in Terminal)
    windows/connect.ps1           # Windows launcher (PowerShell; elevate-when-needed for sshd/firewall)
    connect-ui.sh / connect-ui.ps1 # Shared connect UI + server-only logging
    editor-launch.ps1 / .sh       # Shared VS Code/Cursor launch (dot-sourced by connect)
 windows-mcp-laptop.ps1 # Windows-MCP ensure (dot-sourced by connect.ps1)
    git-mode.ps1 / git-mode.sh    # Shared GIT_MODE helpers + Mac SSH diag upload
    tests/                        # Client regression tests (run-all.bat)
    users/designer/               # Designer-only (noVNC, no editor) Ã¢â‚¬â€ separate product
    users/designer/connect.sh     # Designer Mac launcher: SSHFS + noVNC port forward
    users/designer/connect.ps1    # Designer Windows launcher
    users/designer/connect.bat    # Double-click launcher for Windows
    users/designer/README.md      # End-user quick-start included in designer package
  server/
    claude-server                 # CLI dispatcher Ã¢â€ â€™ /usr/local/bin/claude-server
    commands/
      install.sh                  # Full server install (idempotent)
      add-user.sh                 # Add a developer account
      verify.sh                   # Test all components
      status.sh                   # Show sessions and usage
      sync-auth.sh                # Push OAuth token to all users
      deploy-auth.sh              # Install setup-token + sync + probe + audit log
      sync-cursor-auth.sh         # Push Cursor golden identity to all users
      diagnose-auth.sh            # Auth / login diagnostics
      update-server.sh            # git pull + redeploy
    hooks/                        # Claude Code hooks Ã¢â€ â€™ /usr/local/bin/
    claude-wrapper.sh
    claude-limits.conf
    claude-automount.sh
    claude-auth-sync.sh             # OAuth Ã¢â€ â€™ ~/.claude/settings.json + empty credentials.json
    claude-auth-lib.py              # OAuth audit log, API probe, deploy helpers
    claude-auth-probe.sh            # Cron/manual token probe Ã¢â€ â€™ /var/log/claude-auth.log
    cursor-auth-export.sh           # Export golden Cursor identity Ã¢â€ â€™ /etc/cursor-auth/golden/
    cursor-auth-sync.sh             # Golden identity Ã¢â€ â€™ ~/.config/Cursor/ per user
    cursor-auth-refresh.sh          # Refresh OAuth tokens + re-sync (cron every 6h)
    cursor-auth-lib.py              # Shared Python helpers for export/sync/refresh
    claude-mount.sh               # Pushed to server ~/.local/bin/claude-mount on connect
    claude-git-setup.sh           # Local git mirror; skipped when GIT_MODE=server
    laptop-exec.sh                # SSH-first CLI Ã¢â€ â€™ /usr/local/bin/laptop-exec + per-user ~/.local/bin
    laptop-exec-setup.sh          # Idempotent user/project hook+skill install (project hooks stay EMPTY)
    sudo-from-laptop.sh           # Non-interactive sudo (Smart local / Sepidz via SSH)
    cursor-hooks/                 # Guard wrap, shell-scan, sessionStart, hooks-user/project JSON
    skills/laptop-exec/SKILL.md   # Agent skill (mandatory remap to laptop-exec)
    cursor-rules/laptop-exec.mdc  # Cursor rule (SSH-first)
    commands/deploy-laptop-exec.sh
    claude-connect-logs-cleanup.sh # Hourly: delete ~/.claude/logs older than 1 day
docs/
  client-connect.md               # Client user + developer guide (GIT_MODE, logs, hotkeys, tests)
  sshfs-performance.md            # SSHFS git hide investigation + GIT_MODE
  claude-design.md                # connect-design (claude.ai/design) Ã¢â‚¬â€ separate from users/designer
publish/
  publish.ps1                     # Builds Smart + Sepidz ZIPs (run via publish.bat)
  publish.bat                     # Double-click launcher for publish.ps1
  README.txt                      # Smart package README (IP 192.168.210.240)
  README-sepidz.txt               # Sepidz package README (IP 192.168.250.70) -> claude-code/README.md
```

## Server Commands

```bash
sudo claude-server install        # Full install/redeploy (idempotent, safe to re-run)
sudo claude-server add-user <name>
sudo claude-server verify
sudo claude-server status
sudo claude-server sync-auth      # After token change Ã¢â‚¬â€ pushes OAuth to all ~/.claude/
sudo claude-server deploy-auth <token>  # Install setup-token + sync + probe + audit log
sudo claude-server sync-cursor-auth  # Push Cursor golden identity to all ~/.config/Cursor/
sudo claude-server deploy-mount-fix  # Redeploy mount + automount (ACTIVE_MOUNT single-project)
sudo claude-server deploy-client-bundle  # Publish client scripts for laptop auto-update
sudo claude-server audit-cursor-golden  # Deep golden metadata audit (no secrets printed)
sudo claude-server diagnose-auth  # Find login / OAuth problems
sudo claude-server update-server  # git pull + full redeploy
```

**OAuth auth (automatic after install):** Server token lives root-only in `/etc/claude-code/oauth.env` (mode `0600`). Do **not** put it in world-readable `/etc/environment`. `deploy-auth` / `sync-auth` / `add-user` call `claude-auth-sync` which writes `env.CLAUDE_CODE_OAUTH_TOKEN` into each user's `~/.claude/settings.json` (required for VS Code extension) and resets `~/.claude/.credentials.json` to `{}` (Claude 2.1.x prefers credentials file over env var). Audit log `/var/log/claude-auth.log` is mode `0600`.

**Cursor golden auth (IDE via Remote SSH):** One shared Cursor account + one virtual device for all developers. Golden bundle lives in `/etc/cursor-auth/golden/` (`auth.json`, `state-keys.json`, `storage.json`, `machine-id.txt`) with directory `0700` and files `0600` (root-only). Root `add-user` / `sync-cursor-auth` / cron refresh push copies into each `~/.config/Cursor/`. Bootstrap once on the server (`agent login` or one Remote SSH session), then sync to everyone:

```bash
# After first Remote SSH session or: agent login
sudo cursor-auth-export --from-user smart
sudo claude-server sync-cursor-auth
```

`add-user`, `claude-automount`, `sync-cursor-auth`, and cron (`cursor-auth-refresh` every 6h) keep `~/.config/Cursor/User/globalStorage/` aligned. Laptops only need `cursor.exe` + Remote-SSH Ã¢â‚¬â€ **no per-laptop Cursor login**.

**Chat uses laptop globalStorage Ã¢â‚¬â€ via an isolated profile:** Remote SSH Chat reads the *local* Cursor globalStorage on Windows, not the server's `.cursor-server` storage. `connect.ps1` opens Cursor with `--user-data-dir <LOCALAPPDATA>\ClaudeServerCursorProfile` (`Get-CursorRemoteProfileDir` in `editor-launch.ps1`) Ã¢â‚¬â€ a dedicated profile, separate from the developer's default `%APPDATA%\Cursor` profile. `cursor-auth-sync --force` runs on the server, then `cursor-auth-laptop.ps1` **merges** auth keys into that isolated profile's `state.vscdb` via SQLite UPSERT (never replaces the whole file, never closes any Cursor window). Many server-profile windows share one profile dir Ã¢â‚¬â€ one merge updates all of them. Personal Cursor (`%APPDATA%\Cursor`) is **never read, overwritten, or closed**.

**Corruption safety:** Auth sync does not close or kill any Cursor process (personal or server-profile). Keys are merged in-place into the open `state.vscdb`; WAL sidecar files are never deleted. Profile isolation keeps personal and server logins in separate `--user-data-dir` trees so they can run concurrently without file-lock conflicts on the personal profile.

**Risks:** Cursor ToS prohibits sharing one login across multiple people; concurrent sessions may conflict on refresh tokens. Official alternative: Cursor Teams/Enterprise. See [`scripts/server/CURSOR-AUTH-PILOT.md`](scripts/server/CURSOR-AUTH-PILOT.md) for validation checklist.

**First-time bootstrap** (before `claude-server` is on PATH):
```bash
sudo bash scripts/server/commands/install.sh
# After this, sudo claude-server install works normally
```

**If claude-server not on PATH** (run scripts directly from repo):
```bash
REPO=/path/to/claude-code-server
bash "$REPO/scripts/server/commands/add-user.sh" <name>
```


## Cursor MCP Pack (Remote SSH agents)

Synced into each developer's `~/.cursor/mcp.json` by `cursor-mcp-sync` (also merges HTTP `figma` / `context7` into Claude `~/.claude/settings.json`):

| Server | Notes |
|---|---|
| `figma` | `https://mcp.figma.com/mcp` + golden OAuth `Authorization: Bearer figu_Ã¢â‚¬Â¦` from `/etc/claude-code/figma-mcp.env` (not PAT `figd_`) |
| `context7` | `https://mcp.context7.com/mcp` Ã¢â‚¬â€ no API key required |
| `playwright` | `npx -y @playwright/mcp@latest` |
| `sequential-thinking` | `npx -y @modelcontextprotocol/server-sequential-thinking` |
| `memory` | `npx -y @modelcontextprotocol/server-memory` (per-user `~/.cursor/mcp-memory.jsonl`) |
| `sqlserver` | `/usr/bin/mcp-sqlserver` + env from `/etc/claude-code/sqlserver.env` |

Details: [`docs/cursor-mcp-pack.md`](docs/cursor-mcp-pack.md). After sync: **Reload Window** in Cursor.

## MCP Servers (installed per-user via add-user.sh)

Every user gets these MCP servers wired into `~/.claude/settings.json` automatically:

| MCP Server | Purpose | Install |
|---|---|---|
| `codebase-memory-mcp` | Code knowledge graph Ã¢â‚¬â€ fewer tool calls, cheaper sessions (158-language tree-sitter + Hybrid LSP; replaced `codegraph` 2026-07-23, see `docs/superpowers/plans/2026-07-23-codebase-memory-mcp-rollout.md`) | per-user `install.sh` in `add-user.sh` (step 4b) |
| `headroom` | Context compression Ã¢â‚¬â€ reduces tokens sent to LLM | `pip3 install headroom-ai[mcp]` (step 10) |
| `sqlserver` | SQL Server query access via MCP | `npm install -g @bilims/mcp-sqlserver` |

**SQL Server connection settings** Ã¢â‚¬â€ golden secrets live root-only in `/etc/claude-code/sqlserver.env` (`SQLSERVER_HOST` / `SQLSERVER_USER` / `SQLSERVER_PASSWORD`, mode `0600`). `cursor-mcp-sync` injects them into each user's Cursor `~/.cursor/mcp.json` and Claude `~/.claude/settings.json`. Optional per-user override: `~/.config/cursor-mcp/sqlserver.env`. **Never** commit passwords or bake them into git templates.

```bash
sudo claude-server sync-cursor-mcp          # push pack + SQL + Figma golden to all users
sudo claude-server sync-cursor-mcp USER     # one user
```

To change the shared DB login: edit `/etc/claude-code/sqlserver.env`, then re-run sync (do not sed passwords into homedirs by hand).

**codebase-memory-mcp indexing** Ã¢â‚¬â€ not auto-triggered on login (unlike the old codegraph). Manual trigger inside a project:
```bash
codebase-memory-mcp cli index_repository --repo-path "$(pwd)"
```

## Plugins (installed per-user via add-user.sh)

Every user gets these plugins enabled in `~/.claude/settings.json`:

| Plugin | Purpose | Source |
|---|---|---|
| `superpowers@claude-plugins-official` | Skills system Ã¢â‚¬â€ structured workflows, TDD, debugging, planning | official marketplace |
| `ecc@ecc` | Everything Claude Code Ã¢â‚¬â€ 261 skills, 64 agents, 84 commands | github: affaan-m/ECC |

The `settings.json` template lives in `add-user.sh` step 4 Ã¢â‚¬â€ if you add/remove MCP servers or plugins, update that template.

**Gotcha:** `add-user.sh` must NOT use `chown -R` on `~/home/$user` Ã¢â‚¬â€ SSHFS mounts under `~/mounts/` are owned by the remote user and will fail with `Operation not permitted`, aborting the script. Always chown specific subdirs only (`.claude/`, `.config/Cursor/`, `.local/bin/`, `.ssh/`).

## Connect session logs

**Policy:** zero-loss offline-first. The laptop keeps a **durable local day log** and watermark-syncs to the server when SSH works. Session end does **not** delete the local day file. WARN lines append locally immediately but may lag up to **5s** on the server (coalesced `Request-ConnectLogSync` / `LOG_SYNC_ASYNC scheduled=1` drain); ERROR and session-end always call `Complete-ConnectLogAsyncDrain -Force` so no WARN backlog survives past session end. Details: [`docs/client-connect.md`](docs/client-connect.md#logging).

| Artifact | Path |
|---|---|
| Laptop day log (durable) | Win: `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` Ã‚Â· Mac: `~/.config/claude-connect/logs/connect-YYYYMMDD.log` |
| Server (synced) | `~/.claude/logs/connect-YYYYMMDD.log` |
| Laptop SSH failure diag | `~/.claude/logs/laptop-ssh-diag-latest.txt` (+ timestamped copies) |
| Retention | Laptop + server: delete connect logs `-mtime +1` (client start / sync flush + cron `claude-connect-logs-cleanup`); today's local day file kept until next retention window |

Client UI helpers: `scripts/client/connect-ui.sh` / `connect-ui.ps1`. Deploy: `sudo claude-server install` installs cleanup + `/etc/cron.d/claude-connect-logs`. Details: [`docs/client-connect.md`](docs/client-connect.md).


## SSH-First / laptop-exec (agents)

**Source of truth for agent behavior:** Cursor skill + rule `laptop-exec` (kept short on purpose). Do **not** duplicate that encyclopedia here.

Verified against live `laptop-exec` / hooks. Numbers below are exact.

### Mental model

```
[Cursor agent on Linux]
  Read/Grep/Write on /mounts/ Ã¢â€ â€™ hook DENY (+ NEXT:)
  Shell heavy on mounts Ã¢â€ â€™ DENY
  Task spawn Ã¢â€ â€™ ALLOW (child must still use laptop-exec)
       Ã¢â€ â€œ
[laptop-exec] ControlMaster Ã¢â€ â€™ 127.0.0.1:$TUNNEL_PORT Ã¢â€ â€™ laptop disk
Optional SSHFS ~/mounts/<ID>/ = UI only (may be STALE)
```

Session: `~/.claude-connect.conf`. Cache: `~/.cache/laptop-exec/` (8 `slot-*.lock`, `cm-%C`).

### Hard rules (summary)

1. Denied on mounts: Grep, Glob, Read, Write, Edit, EditNotebook, StrReplace, Delete Ã¢â‚¬â€ run `NEXT:`; never retry.
2. First I/O = Shell + `laptop-exec -p ID` (repo-relative paths only) Ã¢â‚¬â€ **except** on Windows when Cursor MCP `windows-mcp` is ready: prefer `windows-mcp` FileSystem/PowerShell/UI for that step; `git` and content `rg` always stay on `laptop-exec` (full routing table in the skill).
3. `rg` is **not** ripgrep: `-i`/`-l`/`-n`/`--glob` rejected (old hangs pinned mux slots for hours).
4. Mux: **8** slots; prefer Ã¢â€°Â¤4 parallel; `session slots full` Ã¢â€ â€™ wait; no raw SSH storms.
5. Tunnel DOWN Ã¢â€ â€™ user `connect.bat`/`connect.sh`. STALE mount + UP tunnel Ã¢â€ â€™ still laptop-exec.
6. Sudo: `sudo-from-laptop --smart|--sepidz` Ã¢â‚¬â€ never ask for a password.
7. Every Task prompt must paste the SSH-first block from the `laptop-exec` skill.

Project hooks must be exactly `{"version":1,"hooks":{}}`. User hooks use `laptop-exec-guard-wrap.sh` (fail-open). `preToolUse` matcher has **no** Shell (Shell only in `beforeShellExecution`).

CLI: `laptop-exec status|health|list|read|write|rg|git|run|test|help`. Deep ops: `laptop-exec --help` and `scripts/server/skills/laptop-exec/SKILL.md`.

### Related paths

`scripts/server/laptop-exec.sh`, `laptop-exec-setup.sh`, `cursor-hooks/*`, `skills/laptop-exec/SKILL.md`, `cursor-rules/laptop-exec.mdc`, `sudo-from-laptop.sh`, `commands/deploy-laptop-exec.sh`.

## Sync Rule for Server Scripts

When any of these files change, update `scripts/server/commands/install.sh` (the deploy section) and re-run `sudo claude-server install`:

| Changed file | Section to update |
|---|---|
| `scripts/server/hooks/claude-hook-*.sh` | deploy hooks |
| `scripts/server/claude-wrapper.sh` | deploy wrapper |
| `scripts/server/claude-limits.conf` | deploy config |
| `scripts/server/claude-automount.sh` | deploy scripts Ã¢â‚¬â€ `claude-automount` + cron unchanged |
| `scripts/server/claude-auth-sync.sh` | deploy scripts Ã¢â‚¬â€ `install -m 755 Ã¢â‚¬Â¦ /usr/local/bin/claude-auth-sync` |
| `scripts/server/claude-auth-lib.py` | deploy scripts Ã¢â‚¬â€ `/usr/local/lib/claude-server/claude-auth-lib.py` |
| `scripts/server/claude-auth-probe.sh` | deploy scripts Ã¢â‚¬â€ `claude-auth-probe` + `/etc/cron.d/claude-auth-probe` |
| `scripts/server/cursor-auth-export.sh` | deploy scripts Ã¢â‚¬â€ `cursor-auth-export` + golden dir |
| `scripts/server/cursor-auth-sync.sh` | deploy scripts Ã¢â‚¬â€ `cursor-auth-sync` |
| `scripts/server/cursor-auth-refresh.sh` | deploy scripts Ã¢â‚¬â€ `cursor-auth-refresh` + cron |
| `scripts/server/cursor-auth-lib.py` | deploy scripts Ã¢â‚¬â€ `/usr/local/lib/claude-server/cursor-auth-lib.py` |
| `scripts/server/cursor-remote-proxy-sync.sh` | deploy scripts Ã¢â‚¬â€ `cursor-remote-proxy-sync` + `/usr/local/lib/claude-server/` |
| `scripts/server/cursor-auth-source-path.sh` | deploy scripts Ã¢â‚¬â€ `cursor-auth-source-path` |
| `scripts/server/audit-cursor-golden-deep.py` | deploy scripts Ã¢â‚¬â€ `/usr/local/lib/claude-server/audit-cursor-golden-deep.py` |
| `scripts/server/laptop-exec.sh` | deploy scripts Ã¢â‚¬â€ `laptop-exec` + skill + `cursor-rules/laptop-exec.mdc` + `cursor-hooks/` |
| `scripts/server/cursor-hooks/*` | deploy scripts Ã¢â‚¬â€ guard, wrap, shell-scan, session, hooks-user/project (project empty) |
| `scripts/server/claude-connect-logs-cleanup.sh` | deploy scripts Ã¢â‚¬â€ `claude-connect-logs-cleanup` + `/etc/cron.d/claude-connect-logs` |
| `scripts/server/sudo-from-laptop.sh` | deploy scripts Ã¢â‚¬â€ `sudo-from-laptop` (Smart/Sepidz sudo via laptop `*.local.ps1`) |
| `scripts/server/laptop-exec-setup.sh` | deploy scripts Ã¢â‚¬â€ `laptop-exec-setup` |
| `scripts/server/claude-mount.sh` | pushed on connect; also deploy via install.sh Ã¢â€ â€™ `/usr/local/lib/claude-mount` |
| `scripts/server/claude-git-setup.sh` | pushed on connect; skipped when GIT_MODE=server |
| `scripts/server/commands/add-user.sh` | verify settings.json template |
| `scripts/server/commands/deploy-mount-fix.sh` | deploy scripts Ã¢â‚¬â€ `claude-server deploy-mount-fix` |
| `scripts/server/commands/deploy-client-bundle.sh` | deploy scripts Ã¢â‚¬â€ `claude-server deploy-client-bundle` |
| `scripts/server/commands/*.sh` | install copies all to `/usr/local/lib/claude-server/` |

## Client Script Invariants

**Never break these Ã¢â‚¬â€ they are load-bearing:**

| Invariant | Location | Why |
|---|---|---|
| `PORT = 20000 + (UID-1000)*10 + slot` | `Get-TunnelPortUserBase` (git-mode.ps1), `tunnel_port_user_base` (git-mode.sh) | Non-overlapping 10-port block per user (fixed 2026-07-21 Ã¢â‚¬â€ old `20000+UID+slot` overlapped up to 6/10 ports between adjacent UIDs); guard: `20000 < PORT Ã¢â€°Â¤ 65535` |
| `CM='$HOME/.local/bin/claude-mount'` | mac:12, win:28 | Single-quoted Ã¢â‚¬â€ `$HOME` must expand on the REMOTE shell |
| `already_down` / `$alreadyDown` flag | mac:432, win:560 | Prevents double-cleanup in EXIT/finally traps |
| `_editor_opened` / `$editorOpened` flag | mac:434, win:557 | Prevents editor re-opening on tunnel reconnect |
| `_tunnel_alive()` ps state check | mac:590 | `kill -0` returns 0 for zombie processes Ã¢â‚¬â€ must check `ps -o state=` and filter `Z` |
| Single-quote sanitization on user input | mac:294,350-352 win:224,439 | `tr "'" '-'` (bash) / `-replace "'"` (PS) before passing to remote shell |
| `timeout 8 ssh ...` in cleanup | mac:441 | Bounds hang if remote `claude-mount down` gets stuck |
| Both EXIT and SIGTERM traps | mac:444-445 | `kill <pid>` won't trigger EXIT alone |
| `[Console]::Key` + `KeyChar` checks | win:610,728,784 | Physical key check so R/Q/C/X work under Persian/Arabic keyboard layouts |
| `[Uri]::EscapeDataString` for Gateway URL | win:695 | PS5.1+PS7 safe; avoids `System.Web` dependency |
| `$script:ConnectVersion = '20260725.41'` | win connect.ps1 | Must match connect.bat guard |
| `@(Choose-Project -Mounts $mounts)[-1]` | win connect.ps1 | Prevents pipeline leak Ã¢â€ â€™ Join-Path ChildPath prompt |
| `@(Resolve-EditorChoice -CfgDir $CfgDir)[-1]` | win connect.ps1 | Same pipeline-safe capture |
| `return ,($obj)` in Choose-Project | win connect.ps1 | Unary comma suppresses pipeline output |
| `[System.IO.Path]::Combine` in editor-launch | editor-launch.ps1 | Do not use Join-Path for editor.conf paths |
| connect.bat guards | windows/connect.bat | Requires git-mode.ps1, Path.Combine, @(Choose-Project, version |
| Dot-source git-mode.ps1 / git-mode.sh | all Windows/Mac launchers | GIT_MODE must not be duplicated in forks |
| Push GIT_MODE to ~/.claude-connect.conf | connect.ps1/sh | Server claude-mount reads hide vs server |
| `CONNECT_VERSION='20260725.41'` | mac connect.sh | Must match published client version |
| Dot-source `connect-ui.ps1` / source `connect-ui.sh` | all launchers | UI tables, header, session box |
| Elevate only when sshd/firewall/authorized_keys repair needs admin | win | Main UI stays unelevated; `-AdminFix` / `Invoke-LaptopAdminOps` elevates on demand; `Ensure-LaptopSshReady` still used mid-session |
| Publish client package **12 files** | publish.ps1 | +connect-ui, editor-launch.sh (mac) |
| `CONNECT_PORT_BASE=20000` | mac connect.sh | Port formula base; guard: `base < PORT Ã¢â€°Â¤ 65535` |
| `exit_requested` menu loop + M/C/X | mac connect.sh | Post-disconnect menu parity with Windows |
| `clear_session_mount` on disconnect | mac via git-mode.sh | Close editor + down + clear ACTIVE_MOUNT |
| `initialize_server_session` | mac via git-mode.sh | Parallel scp + single "Server setup" step |
| EXIT + SIGTERM + **SIGHUP** traps | mac connect.sh | Terminal close must cleanup mount |
| `Push-ServerConnectConf -ActiveMount` | win + designer | Single-project mount; clear on disconnect |

## Designer Script Invariants (`users/designer/`)

**Additional invariants for the designer connect scripts:**

| Invariant | Location | Why |
|---|---|---|
| EXIT + SIGTERM + **SIGHUP** traps | designer/connect.sh | Terminal close sends SIGHUP Ã¢â‚¬â€ without it, server mount is left dangling |
| `_novnc_opened=1` inside success branch only | designer/connect.sh | Set only when noVNC opens successfully; stays 0 on failure so reconnect retries |
| `$novncOpened = $true` inside success branch only | designer/connect.ps1 | Same Ã¢â‚¬â€ do NOT set in the else/fail branch |
| `$autoFixCount` reset to 0 on manual R reconnect | designer/connect.ps1 | Prevents permanent loss of auto-fix attempts across reconnects; do NOT reset on auto-reconnect `continue` |
| `grep -E "^${MOUNT_ID}\|"` with escaped pipe | designer/connect.sh | ERE mode required; unescaped `\|` in BRE alternation breaks on `grep -E` aliases |
| Conf validated after source: `LAPTOP_USER` + `LAPTOP_PATH` non-empty | both | `set -uo pipefail` / PowerShell dies with cryptic error on unset vars Ã¢â‚¬â€ explicit die with clear message |
| `$SshDir` ACL grants both `$env:USERNAME` AND `$LaptopUser` when they differ | designer/connect.ps1 | Windows sshd reads `authorized_keys` under `$LaptopUser` token Ã¢â‚¬â€ directory must be listable by that user |
| `-L "127.0.0.1:${NOVNC_PORT}:127.0.0.1:${NOVNC_PORT}"` in tunnel | both | noVNC websockify binds `127.0.0.1` only Ã¢â‚¬â€ must forward via SSH local port, not direct LAN |

## macOS SSH Detection (Three Layers)

`pgrep -x sshd` is unreliable on macOS with on-demand launchd SSH. Use this order:

1. `nc -zw1 127.0.0.1 22` Ã¢â‚¬â€ fastest
2. `launchctl print system/com.openssh.sshd | grep -q 'state = running'`
3. `launchctl list com.openssh.sshd >/dev/null 2>&1` Ã¢â‚¬â€ exit code only (grep on output is a false positive)
4. `systemsetup -getremotelogin` Ã¢â‚¬â€ slow fallback, requires sudo on newer macOS

## Client Codebase (Smart + Sepidz)

**One codebase** Ã¢â‚¬â€ `windows/connect.ps1` + `mac/connect.sh`. Same alias (`claude-server`), cfg (`~/.config/claude-connect`), port base (`20000 + (UID-1000)*10`, 10-slot non-overlapping block per user).

**Sepidz vs Smart differs only at publish time:** `publish.ps1` builds two ZIPs; the Sepidz package copies the same client scripts with `SERVER_IP` patched (`192.168.210.240 -> 192.168.250.70`) in `connect.ps1`, `connect.sh`, and designer connect scripts. Package READMEs: `publish/README.txt` (Smart) vs `publish/README-sepidz.txt` (Sepidz). **Do not** maintain a separate `users/sepidz/` fork.

**Designer** (`users/designer/`) is a separate product (noVNC, no editor) Ã¢â‚¬â€ also gets IP patch in the Sepidz ZIP only.

**Client sync rule:** Editor-launch changes go in `scripts/client/editor-launch.ps1` only. Git-mode changes go in `scripts/client/git-mode.ps1` / `git-mode.sh`. All launchers dot-source them. `publish.ps1` copies them into ZIP packages.

## Self-Healing Behaviours

The client scripts handle these automatically without user intervention:

| Problem | Auto-fix |
|---|---|
| SSH key rejected by laptop | Reinstall server's `claude_laptop.pub` into `authorized_keys` and retry |
| Windows sshd stopped | `Start-Service sshd` with up-to-20s readiness wait |
| Windows OpenSSH Server not installed | `Add-WindowsCapability` install; fallback to `winget`; Windows Update service auto-started if needed |
| Windows firewall SSH rule missing/disabled | `New-NetFirewallRule` / `Enable-NetFirewallRule` (Profile Any enforced) |
| Stale SSHFS mount | `claude-mount recover` before each `up` |
| Cursor login despite auth ok (Mac) | Soft-stop server profile after auth; write `machineid`; require full remote path for folder match |
| Mac SSH allow-list blocked | Remove user from `com.apple.access_ssh-disabled`; add to `com.apple.access_ssh` |
| Tunnel drops during session | Auto-reconnect loop; editor not re-opened on reconnect |
| SSH permission errors (Windows) | `icacls` fixes on `.ssh/`, `authorized_keys`, `config`, `administrators_authorized_keys` |
| sshd restart kills tunnel | Re-check `Test-Tunnel` before retrying mount after forced restart |
| macOS Remote Login OFF | `systemsetup -setremotelogin on` + 10s wait for sshd to accept connections |
| Git hide fails (Cursor lock) | Retry rename 3Ãƒâ€”; stop git.exe on attempt 2; warn user; `G` remount |
| GIT_MODE=server selected | Skip claude-git-setup mirror; `.git` visible on SSHFS (slow) |
| Stale foreign `LAPTOP_USER` in conf (tunnel port down) | Clear `~/.claude-connect.conf` and continue |
| Mac/Windows-incompatible mount `rpath` | Purge incompatible `~/.claude-mounts.d/*.conf` entries |
| Laptop SSH auth failure (Mac) | `diagnose_laptop_ssh_failure` uploads diag to server `~/.claude/logs/` |
| Multi-agent Ã¢â‚¬Å“everyone blockedÃ¢â‚¬Â | Ensure project `hooks.json` empty; user hooks use wrap; no Shell in `preToolUse`; slots/mux healthy; Task prompts force laptop-exec |
| Tunnel flapping / MaxStartups | Stop concurrent SSH storms; `connect` raises MaxSessions/MaxStartups; do not stress-test tunnel |
| Guard syntax error locking tools | Wrap fail-opens; fix guard; never point hooks at raw guard without wrap |
| Project hooks refilled | `laptop-exec-setup` must write empty project hooks only; re-empty `~/mounts/*/.cursor/hooks.json` |
| Mac admin password prompts | At most once per run (45s timeout); skip Remote Login cycle if already on |

## Client Regression Tests

Location: `scripts/client/tests/`

```bat
scripts\client\tests\run-all.bat
```

| Script | Purpose |
|---|---|
| `test-pipeline-deep.ps1` | PowerShell pipeline semantics |
| `test-pipeline-repro.ps1` | Join-Path bug reproduction |
| `test-select-project.ps1` | Post-select capture pattern |
| `test-connect-pipeline.ps1` | connect.ps1 invariants |
| `test-git-mode-deep.ps1` | GIT_MODE client + server |
| `test-editor-launch.ps1` | Editor CLI on PATH |
| `audit-local-connect.ps1` | Find stale connect.ps1 copies on laptop |

Shared helpers: `tests/_paths.ps1`. Full guide: [`docs/client-connect.md`](docs/client-connect.md).

## Publish Workflow

Run on **smart's Windows laptop** to build distributable packages:

```
publish\publish.bat
```

Outputs to `Desktop\claude-publish\`:

| Package | Contents | Notes |
|---|---|---|
| `claude-code-client.zip` | `windows/` + `mac/` + `README.txt` | Smart IP `192.168.210.240`; client only - **no `server/`** |
| `claude-code-sepidz.zip` | `claude-code/` + `designer/` + READMEs | Sepidz IP `192.168.250.70`; scripts IP-patched; README from `README-sepidz.txt` |

**Client-only rule:** Published ZIPs must never contain `server/`, `deploy-mount-fix.sh`, or `deploy-server-mount-fix.*`. Server deploy runs from repo `scripts/client/deploy-server-mount-fix.bat` (admin, smart laptop).

**IP patching (Sepidz package only):** `publish.ps1` replaces `192.168.210.240 -> 192.168.250.70` in `connect.ps1`, `connect.sh`, and designer connect scripts. Package READMEs stay separate (`publish/README.txt` vs `publish/README-sepidz.txt`). Logging policy is the same on both sites. No separate alias, cfg dir, or port base.

**Sepidz package structure:**
```nclaude-code-sepidz-YYYYMMDD/
  claude-code/          # windows/ + mac/ (IP patched) + README.md from README-sepidz.txt
  designer/             # designer scripts (IP patched) + README.md
```

## Designer: Chrome Download Directory

Chrome is configured via **managed policy** (not Preferences) so the setting survives Chrome restarts:

```
/etc/opt/chrome/policies/managed/designer-download.json
DownloadDirectory = /home/designer/mounts/laptop
```

**Gotcha:** Do NOT edit Chrome Preferences directly Ã¢â‚¬â€ Chrome overwrites them on close.
The managed policy is set automatically by `install.sh`.
After running deploy, designer must disconnect/reconnect once for Chrome to pick it up.

## Removed Legacy Scripts

These were deleted from the repo Ã¢â‚¬â€ use `claude-server` instead:

| Old (removed) | Replacement |
|---|---|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user <name>` |
| `install-designer-deps.sh` | part of `claude-server install` |
| `setup-designer.sh` | part of `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
