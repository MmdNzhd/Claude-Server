# Client Connect — Developer & User Guide

Current client version: **`20260703.12`**

## What It Does

```
Laptop (connect.bat / connect.sh)
  ├─ SSH reverse tunnel  server:20000+UID → laptop:22
  ├─ Push ~/.claude-connect.conf (GIT_MODE, LAPTOP_OS, TUNNEL_PORT)
  ├─ Push claude-mount + claude-git-setup to server ~/.local/bin/
  ├─ claude-mount recover → up <project>
  └─ Open Cursor/VS Code via Remote SSH
```

Files stay on the laptop. The server reads them through SSHFS over the reverse tunnel.

---

## Windows Package Contents

Every **Windows** connect folder must contain **all seven** files side by side:

| File | Role |
|------|------|
| `connect.bat` | Launcher + outdated-script guard (`-STA` for folder picker) |
| `connect.ps1` | Main script (tunnel, mount, editor) |
| `connect-ui.ps1` | Header, project table, session box, title, toast |
| `editor-launch.ps1` | Cursor/VS Code Remote SSH + IDE pref (`ask`) |
| `git-mode.ps1` | GIT_MODE, post-disconnect, last project |
| `cursor-auth-laptop.ps1` | Golden auth sync to isolated profile |
| `connect-rider.bat` | Optional — `-Ide cursor` shortcut |

Mac folders need `connect.sh`, `git-mode.sh`, `connect-ui.sh`, `editor-launch.sh` (12 client files total in ZIP).

Published by `publish\publish.bat` → `Desktop\claude-publish\`.

---

## First Run Checklist

1. Double-click `connect.bat` (or `bash mac/connect.sh`).
2. Header must show:
   ```
   claude-server  |  192.168.210.240  |  v20260703.12
   ```
3. Project menu shows **git banner** (FAST/SLOW) and table with laptop paths; footer includes **`g git`**:
   ```
   a add   e edit   d delete   c config   g git   q quit
   ```
4. Select a project number — must **not** prompt `Join-Path ChildPath:`.
5. **Enter** at empty prompt selects last project (if `last.conf` exists).

If version is missing, menu has no `g git`, or `ChildPath` appears → **old copy**. Re-copy from latest ZIP or `Desktop\Claude-Connect\`.

`connect.bat` refuses to start if any guard fails (missing `git-mode.ps1`, wrong version, no `@(Choose-Project` in `connect.ps1`, etc.).

---

## Session Hotkeys

| Key | When | Action |
|-----|------|--------|
| `R` | Active session | Reconnect tunnel + remount |
| `Q` / Enter | Active session | Disconnect, close editor, restore `.git` on laptop |
| `G` | Active session | Change git mode + remount current project |
| `g` | Project menu | Change git mode (before session starts) |
| `P` | Active session (bootstrap only) | Push server login from [Claude Server] to golden |
| `M` | After disconnect | Back to project menu (default after 10s countdown) |
| `C` | After disconnect | Connect again (same project) |
| `X` | After disconnect | Exit connect script |

Windows: physical key detection (works with Persian/Arabic keyboard).  
Mac: same keys via terminal read.

---

## Single-Project Mount (ACTIVE_MOUNT)

Only the **selected** project is mounted per session. Other projects stay unmounted so `.git` is not touched on every laptop folder.

| Layer | Mechanism |
|-------|-----------|
| Client | `Push-ServerConnectConf -ActiveMount <id>` + `down-others` before `up` |
| Server runtime | `~/.claude-connect.conf` → `ACTIVE_MOUNT=ai` |
| Login guard | `claude-automount` runs `up "$ACTIVE_MOUNT"` only (not bulk mount) |

On disconnect, `ACTIVE_MOUNT` is cleared so automount does not remount stale projects.

**Designer:** always `ACTIVE_MOUNT=laptop` (single mount id).

---

## Mac Package

| File | Role |
|------|------|
| `mac/connect.sh` | Main launcher (v20260703.12 in header) |
| `mac/git-mode.sh` | GIT_MODE, Cursor P-key, post-disconnect |
| `mac/connect-ui.sh` | Header, project table, session box |
| `mac/editor-launch.sh` | IDE pick (`ask` / cursor / code) |

Cursor on Mac uses isolated profile: `~/Library/Application Support/ClaudeServerCursorProfile` (same idea as Windows `ClaudeServerCursorProfile`).

```bash
bash mac/connect.sh
# header: claude-server  |  192.168.210.240  |  v20260703.12
```

Sepidz users get the same scripts from `claude-code-sepidz-*.zip`; publish patches only the IP to `192.168.250.70`.

## GIT_MODE — FAST vs SLOW Git

Display labels in v12: **FAST** (internal `hide`) and **SLOW** (internal `server`).

| Mode | Laptop | Server mount | Server git |
|------|--------|--------------|------------|
| **hide** (default) | `.git` → `.git.server-session` | No `.git` visible | Fast — local mirror via `claude-git-setup` |
| **server** | `.git` stays | `.git` over SSHFS | Slow — full SSHFS stat traffic |

**Laptop preference:** `%USERPROFILE%\.config\claude-connect\git.conf` → `hide` or `server`

**Server runtime:** `~/.claude-connect.conf`:
```
LAPTOP_USER=Smart
TUNNEL_PORT=21002
GIT_MODE=hide
LAPTOP_OS=windows
ACTIVE_MOUNT=ai
```

**Per-project override (server only):** add to `~/.claude-mounts.d/<id>.conf`:
```
git_mode=server
```

**If hide fails** (Cursor locks `.git`): warning `warn: git hide failed …` — close Remote SSH on laptop, press `G` → Off (fast) to retry. Mount retries rename 3× and stops `git.exe` on attempt 2.

**Designer:** mount id is always `laptop`; same `G` / `git.conf` behaviour.

See also: [sshfs-performance.md](sshfs-performance.md) — full performance investigation.

---

## Cursor Chat Auth (Golden — No Laptop Login)

Chat/Composer in Remote SSH still reads **laptop** `%APPDATA%\Cursor\User\globalStorage\state.vscdb`.  
You do **not** need to stay logged in on the laptop — `connect.bat` syncs golden tokens from the server before opening Cursor:

1. Server: `cursor-auth-sync --force` (from `/etc/cursor-auth/golden/`)
2. Laptop: pulls `state.vscdb` + `storage.json` from server

If Chat still asks to log in after a local logout: close all Cursor windows, run `connect.bat` again, or `Developer: Reload Window`.

**Do not** use Sign Out in local Cursor if a remote session is open — it can invalidate shared tokens. Use connect instead.

Admin bootstrap (once): `sudo cursor-auth-export --from-user smart` then `sudo claude-server sync-cursor-auth`

---

**Symptom:** After selecting project `1`, PowerShell prompts:
```
cmdlet Join-Path at command pipeline position 1
Supply values for the following parameters:
ChildPath:
```

**Cause:** Old `connect.ps1` emitted a PSCustomObject into the pipeline; the next `Join-Path` in `editor-launch.ps1` bound it as `-Path` and waited for `ChildPath`.

**Fix (all required):**
- `Choose-Project` function with `return ,($obj)` (unary comma)
- `$go = @(Choose-Project -Mounts $mounts)[-1]`
- `$editorChoice = @(Resolve-EditorChoice -CfgDir $CfgDir)[-1]`
- `editor-launch.ps1` uses `[System.IO.Path]::Combine` instead of `Join-Path`

Do **not** use stale Desktop copies, old `claude-publish\20260630\`, or folders without `git-mode.ps1`.

---

## Shared Modules (Do Not Duplicate)

| Module | Used by |
|--------|---------|
| `scripts/client/connect-ui.ps1` | windows connect launchers |
| `scripts/client/connect-ui.sh` | mac connect |
| `scripts/client/editor-launch.ps1` | windows connect launchers |
| `scripts/client/editor-launch.sh` | mac connect |
| `scripts/client/git-mode.ps1` | windows connect + designer |
| `scripts/client/git-mode.sh` | mac connect + designer |
| `scripts/client/cursor-auth-laptop.ps1` | windows connect only |

Changes go in the shared file only. `publish.ps1` copies them into each ZIP subfolder.

---

## Regression Tests

Location: `scripts/client/tests/`

```bat
scripts\client\tests\run-all.bat
```

| Script | Covers |
|--------|--------|
| `test-pipeline-deep.ps1` | PowerShell pipeline semantics (MS docs) |
| `test-pipeline-repro.ps1` | Join-Path bug demonstration |
| `test-select-project.ps1` | Post-select capture pattern |
| `test-connect-ui.ps1` | Layout tiers, path truncation, no console resize |
| `test-connect-pipeline.ps1` | connect.ps1 invariants + claude-mount |
| `test-git-mode-deep.ps1` | GIT_MODE client + server |
| `test-editor-launch.ps1` | Editor CLI on PATH |
| `audit-local-connect.ps1` | Scan laptop for stale connect.ps1 copies |

Shared paths: `tests/_paths.ps1` (`ClientRoot`, `ScriptsRoot`, `RepoRoot`).

---

## Server Side (Admin)

Published client ZIPs are **client-only** (no `server/` folder). Server scripts live in the repo under `scripts/server/`.

**Deploy mount fix to ALL users** (ACTIVE_MOUNT, down-others, EncodedCommand git hide) — **repo only**, VPN + sudo:

```bat
scripts\client\deploy-server-mount-fix.bat
```

Or from smart's Desktop sync folder (deploy scripts copied from repo, not from ZIP):

```bat
Desktop\Claude-Connect\deploy-server-mount-fix.bat
```

Or:

```powershell
scripts\client\sync-desktop.ps1 -DeployServer
```

On server:

```bash
sudo claude-server deploy-mount-fix
# or
sudo bash ~/claude-mount-deploy/deploy-mount-fix.sh
```

For **full install** + system lib:

```bash
sudo claude-server install    # idempotent
sudo claude-server verify     # checks GIT_MODE in /usr/local/lib/claude-mount
```

Individual user may have newer `~/.local/bin/claude-mount` than `/usr/local/lib/` until deploy/install runs.

**Admin one-click (smart laptop):** `scripts\client\sync-desktop.bat` — publish + sync Desktop + tests. Add `-DeployServer` for server deploy when VPN is on.

---

## Smart vs Sepidz

One codebase (`windows/` + `mac/`). `publish.ps1` builds two ZIPs; Sepidz package = same files with `SERVER_IP` patched only. Do not maintain separate connect forks per server.

---

## Troubleshooting

| Problem | Check |
|---------|-------|
| `ChildPath` after project select | Version not `.12`? All 7 Windows files present? |
| `g git` missing in menu | Old connect.ps1 (check connect-ui.ps1 too) |
| connect.bat OUTDATED | Missing connect-ui.ps1 or wrong ConnectVersion |
| All projects mounted / `.git` broken | Admin deploy mount fix; reconnect with v12 |
| Hide git failed | Close Cursor; `G` → FAST; or stop git on laptop |
| Tunnel drops during recover | Auto-reconnect + toast; tunnel re-checked after `recover` |
| Editor stays open after Q | Need v12 + `Clear-SessionMount` |
| No back to menu after disconnect | Need v12 post-disconnect (10s → M) |
| UAC every run (old) | v12 only prompts when sshd/firewall/key needs admin fix |

Run audit:
```powershell
powershell -File scripts\client\tests\audit-local-connect.ps1
```
