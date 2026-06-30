# Claude Code Server — Project Rules

## Language Rule

**No Persian text in scripts.** Persian is allowed only in documentation files (CLAUDE.md, READMEs).
All scripts (`*.sh`, `*.ps1`, `*.bat`) must use English only — comments, variable names, error messages.

## Architecture Overview

SSH reverse tunnel: client laptop → server, port = `20000 + server_UID`.
Server does SSHFS back to the laptop through that tunnel; the laptop has no local SSHFS mount.
Each `sshx()` (Mac) / `SshX()` (Windows) call opens a new TCP SSH connection — no multiplexing.

```
Laptop ──SSH──▶ Server (port 22)
Server ──SSHFS──▶ Laptop (via reverse tunnel on port 20000+UID)
```

## File Map

```
scripts/
  client/
    mac/connect.sh                # Mac launcher (bash, runs in Terminal)
    windows/connect.ps1           # Windows launcher (PowerShell, self-elevates to admin)
    editor-launch.ps1             # Shared VS Code/Cursor launch (dot-sourced by connect.ps1)
    users/<name>/connect.ps1      # Per-user Windows forks (e.g. sepidz) — IP/alias/cfg only
    users/<name>/connect.sh       # Per-user Mac forks (e.g. sepidz)
    users/designer/connect.sh     # Designer Mac launcher: SSHFS + noVNC port forward (no editor)
    users/designer/connect.ps1    # Designer Windows launcher: SSHFS + noVNC port forward (no editor)
    users/designer/connect.bat    # Double-click launcher for Windows
    users/designer/README.md      # End-user quick-start included in designer package
  server/
    claude-server                 # CLI dispatcher → /usr/local/bin/claude-server
    commands/
      install.sh                  # Full server install (idempotent)
      add-user.sh                 # Add a developer account
      verify.sh                   # Test all components
      status.sh                   # Show sessions and usage
      sync-auth.sh                # Push OAuth token to all users
      diagnose-auth.sh            # Auth / login diagnostics
      update-server.sh            # git pull + redeploy
    hooks/                        # Claude Code hooks → /usr/local/bin/
    claude-wrapper.sh
    claude-limits.conf
    claude-automount.sh
    claude-auth-sync.sh             # OAuth → ~/.claude/settings.json + empty credentials.json
    claude-mount.sh               # Pushed to server ~/.local/bin/claude-mount on connect
publish/
  publish.ps1                     # Builds distributable ZIP packages (run via publish.bat)
  publish.bat                     # Double-click launcher for publish.ps1
  README.txt                      # Included in the main (smart) package
```

## Server Commands

```bash
sudo claude-server install        # Full install/redeploy (idempotent, safe to re-run)
sudo claude-server add-user <name>
sudo claude-server verify
sudo claude-server status
sudo claude-server sync-auth      # After token change — pushes OAuth to all ~/.claude/
sudo claude-server diagnose-auth  # Find login / OAuth problems
sudo claude-server update-server  # git pull + full redeploy
```

**OAuth auth (automatic after install):** Server token lives in `/etc/environment` + `/etc/profile.d/claude-auth.sh`. `add-user`, `claude-automount` (on login), and `sync-auth` call `claude-auth-sync` which writes `env.CLAUDE_CODE_OAUTH_TOKEN` into each user's `~/.claude/settings.json` (required for VS Code extension) and resets `~/.claude/.credentials.json` to `{}` (Claude 2.1.x prefers credentials file over env var).

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

## MCP Servers (installed per-user via add-user.sh)

Every user gets these MCP servers wired into `~/.claude/settings.json` automatically:

| MCP Server | Purpose | Install |
|---|---|---|
| `codegraph` | Code knowledge graph — fewer tool calls, cheaper sessions | step 9 in `install.sh` |
| `headroom` | Context compression — reduces tokens sent to LLM | `pip3 install headroom-ai[mcp]` (step 10) |
| `sqlserver` | SQL Server query access via MCP | `npm install -g @bilims/mcp-sqlserver` |

**SQL Server connection settings** — stored in `~/.claude/settings.json` under `mcpServers.sqlserver.env`. Each user can edit their own file to change the connection:

```json
"sqlserver": {
  "type": "stdio",
  "command": "/usr/bin/mcp-sqlserver",
  "args": [],
  "env": {
    "SQLSERVER_HOST": "192.168.210.124",
    "SQLSERVER_USER": "Mohammad",
    "SQLSERVER_PASSWORD": "Mohammad123"
  }
}
```

To update the IP for all users at once (run as root on server):
```bash
for user in smart amir amirhossein aria danial hamed hamed.kh kiana mahdie mehrdad mohammad parsa reza tarane; do
  f="/home/$user/.claude/settings.json"
  [ -f "$f" ] && sed -i 's/OLD_IP/NEW_IP/g' "$f" && echo "✓ $user"
done
```

**CodeGraph per-project indexing** — runs automatically on login via `claude-automount`. Manual trigger:
```bash
codegraph init   # run inside project dir if .codegraph/ is missing
```

## Plugins (installed per-user via add-user.sh)

Every user gets these plugins enabled in `~/.claude/settings.json`:

| Plugin | Purpose | Source |
|---|---|---|
| `superpowers@claude-plugins-official` | Skills system — structured workflows, TDD, debugging, planning | official marketplace |
| `ecc@ecc` | Everything Claude Code — 261 skills, 64 agents, 84 commands | github: affaan-m/ECC |

The `settings.json` template lives in `add-user.sh` step 4 — if you add/remove MCP servers or plugins, update that template.

**Gotcha:** `add-user.sh` must NOT use `chown -R` on `~/home/$user` — SSHFS mounts under `~/mounts/` are owned by the remote user and will fail with `Operation not permitted`, aborting the script. Always chown specific subdirs only (`.claude/`, `.local/bin/`, `.ssh/`).

## Sync Rule for Server Scripts

When any of these files change, update `scripts/server/commands/install.sh` (the deploy section) and re-run `sudo claude-server install`:

| Changed file | Section to update |
|---|---|
| `scripts/server/hooks/claude-hook-*.sh` | deploy hooks |
| `scripts/server/claude-wrapper.sh` | deploy wrapper |
| `scripts/server/claude-limits.conf` | deploy config |
| `scripts/server/claude-automount.sh` | deploy scripts — or: `install -m 755 claude-automount.sh /usr/local/bin/claude-automount` |
| `scripts/server/claude-auth-sync.sh` | deploy scripts — `install -m 755 … /usr/local/bin/claude-auth-sync` |
| `scripts/server/commands/add-user.sh` | verify settings.json template |
| `scripts/server/commands/*.sh` | install copies all to `/usr/local/lib/claude-server/` |

## Client Script Invariants

**Never break these — they are load-bearing:**

| Invariant | Location | Why |
|---|---|---|
| `PORT = 20000 + server_UID` | mac:203, win:361 | Port formula; guard: `20000 < PORT ≤ 65535` |
| `PORT = 21000 + server_UID` | users/sepidz/connect.sh, users/sepidz/connect.ps1 | Port formula for sepidz fork (base 21000 isolates from smart UID space); guard: `21000 < PORT ≤ 65535` |
| `CM='$HOME/.local/bin/claude-mount'` | mac:12, win:28 | Single-quoted — `$HOME` must expand on the REMOTE shell |
| `already_down` / `$alreadyDown` flag | mac:432, win:560 | Prevents double-cleanup in EXIT/finally traps |
| `_editor_opened` / `$editorOpened` flag | mac:434, win:557 | Prevents editor re-opening on tunnel reconnect |
| `_tunnel_alive()` ps state check | mac:590 | `kill -0` returns 0 for zombie processes — must check `ps -o state=` and filter `Z` |
| Single-quote sanitization on user input | mac:294,350-352 win:224,439 | `tr "'" '-'` (bash) / `-replace "'"` (PS) before passing to remote shell |
| `timeout 8 ssh ...` in cleanup | mac:441 | Bounds hang if remote `claude-mount down` gets stuck |
| Both EXIT and SIGTERM traps | mac:444-445 | `kill <pid>` won't trigger EXIT alone |
| `[Console]::Key` + `KeyChar` checks | win:610,728,784 | Physical key check so R/Q/C/X work under Persian/Arabic keyboard layouts |
| `[Uri]::EscapeDataString` for Gateway URL | win:695 | PS5.1+PS7 safe; avoids `System.Web` dependency |

## Designer Script Invariants (`users/designer/`)

**Additional invariants for the designer connect scripts:**

| Invariant | Location | Why |
|---|---|---|
| EXIT + SIGTERM + **SIGHUP** traps | designer/connect.sh | Terminal close sends SIGHUP — without it, server mount is left dangling |
| `_novnc_opened=1` inside success branch only | designer/connect.sh | Set only when noVNC opens successfully; stays 0 on failure so reconnect retries |
| `$novncOpened = $true` inside success branch only | designer/connect.ps1 | Same — do NOT set in the else/fail branch |
| `$autoFixCount` reset to 0 on manual R reconnect | designer/connect.ps1 | Prevents permanent loss of auto-fix attempts across reconnects; do NOT reset on auto-reconnect `continue` |
| `grep -E "^${MOUNT_ID}\|"` with escaped pipe | designer/connect.sh | ERE mode required; unescaped `\|` in BRE alternation breaks on `grep -E` aliases |
| Conf validated after source: `LAPTOP_USER` + `LAPTOP_PATH` non-empty | both | `set -uo pipefail` / PowerShell dies with cryptic error on unset vars — explicit die with clear message |
| `$SshDir` ACL grants both `$env:USERNAME` AND `$LaptopUser` when they differ | designer/connect.ps1 | Windows sshd reads `authorized_keys` under `$LaptopUser` token — directory must be listable by that user |
| `-L "127.0.0.1:${NOVNC_PORT}:127.0.0.1:${NOVNC_PORT}"` in tunnel | both | noVNC websockify binds `127.0.0.1` only — must forward via SSH local port, not direct LAN |

## macOS SSH Detection (Three Layers)

`pgrep -x sshd` is unreliable on macOS with on-demand launchd SSH. Use this order:

1. `nc -zw1 127.0.0.1 22` — fastest
2. `launchctl print system/com.openssh.sshd | grep -q 'state = running'`
3. `launchctl list com.openssh.sshd >/dev/null 2>&1` — exit code only (grep on output is a false positive)
4. `systemsetup -getremotelogin` — slow fallback, requires sudo on newer macOS

## Per-User Forks (`scripts/client/users/<name>/`)

Every user fork **must** include these three things, or self-healing breaks:

1. Early `ssh.exe` / `ssh` PATH check immediately after `$ErrorActionPreference = "Continue"`
2. `$editorOpened = $false` declared before `:mainLoop`
3. All editor-open logic wrapped in `if (-not $editorOpened) { ... }`

When creating a new user fork, copy from `scripts/client/windows/connect.ps1` and update `$ServerIP` (and alias/cfg dir). Editor launch logic lives in `editor-launch.ps1` — do not duplicate it.

**Client sync rule:** Editor-launch changes go in `scripts/client/editor-launch.ps1` only. Both `windows/connect.ps1` and `users/sepidz/connect.ps1` dot-source it. `publish.ps1` copies `editor-launch.ps1` next to each `connect.ps1` in both ZIP packages.

## Self-Healing Behaviours

The client scripts handle these automatically without user intervention:

| Problem | Auto-fix |
|---|---|
| SSH key rejected by laptop | Reinstall server's `claude_laptop.pub` into `authorized_keys` and retry |
| Windows sshd stopped | `Start-Service sshd` with up-to-20s readiness wait |
| Windows OpenSSH Server not installed | `Add-WindowsCapability` install; fallback to `winget`; Windows Update service auto-started if needed |
| Windows firewall SSH rule missing/disabled | `New-NetFirewallRule` / `Enable-NetFirewallRule` (Profile Any enforced) |
| Stale SSHFS mount | `claude-mount recover` before each `up` |
| Tunnel drops during session | Auto-reconnect loop; editor not re-opened on reconnect |
| SSH permission errors (Windows) | `icacls` fixes on `.ssh/`, `authorized_keys`, `config`, `administrators_authorized_keys` |
| sshd restart kills tunnel | Re-check `Test-Tunnel` before retrying mount after forced restart |
| macOS Remote Login OFF | `systemsetup -setremotelogin on` + 10s wait for sshd to accept connections |

## Publish Workflow

Run on **smart's Windows laptop** to build distributable packages:

```
publish\publish.bat
```

Outputs to `Desktop\claude-publish\`:

| Package | Contents | Notes |
|---|---|---|
| `claude-code-client-YYYYMMDD.zip` | `windows/` + `mac/` + README.txt | Generic (smart server `192.168.210.240`) |
| `claude-code-sepidz-YYYYMMDD.zip` | `claude-code/` + `designer/` + READMEs | Sepidz server `192.168.250.70` |

**Gotcha — IP patching:** The designer scripts (`users/designer/`) hardcode smart's server IP (`192.168.210.240`). `publish.ps1` automatically replaces this with sepidz's IP (`192.168.250.70`) when building the sepidz package. Only `connect.ps1` and `connect.sh` are patched — `connect.bat` contains no IP.

**Sepidz package structure:**
```
claude-code-sepidz-YYYYMMDD/
  claude-code/          ← sepidz developer scripts + README.md (quick-start.md)
    windows/ mac/
  designer/             ← designer scripts (IP patched to 192.168.250.70) + README.md
    windows/ mac/
```

## Designer: Chrome Download Directory

Chrome is configured via **managed policy** (not Preferences) so the setting survives Chrome restarts:

```
/etc/opt/chrome/policies/managed/designer-download.json
DownloadDirectory = /home/designer/mounts/laptop
```

**Gotcha:** Do NOT edit Chrome Preferences directly — Chrome overwrites them on close.
The managed policy is set automatically by `install.sh`.
After running deploy, designer must disconnect/reconnect once for Chrome to pick it up.

## Deprecated Scripts

Do not use — kept for reference only:

| Old | Replacement |
|---|---|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user <name>` |
| `install-designer-deps.sh` | part of `claude-server install` |
| `setup-designer.sh` | part of `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
