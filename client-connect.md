# Client Connect Guide

Developer and end-user guide for `connect.bat` / `connect.sh`.

**Current client version:** **`20260720.12`**

See also: [sshfs-performance.md](sshfs-performance.md) (GIT_MODE deep dive), [CLAUDE.md](../CLAUDE.md) (server admin).

---

## Architecture

```
Laptop (Windows/Mac)
  connect.bat / connect.sh
    reverse SSH tunnel  ->  server port 20000 + UID
    pushes ~/.claude-connect.conf (GIT_MODE, ACTIVE_MOUNT, TUNNEL_PORT)

Server (Linux)
  claude-mount up <id>  ->  SSHFS ~/mounts/<id>  <- laptop folder via tunnel
  Cursor/VS Code Remote SSH opens vscode-remote://ssh-remote+claude-server/...
```

Windows `ssh` calls are usually separate TCP connections. Mac `sshx()` reuses one SSH ControlMaster connection for the session (faster setup). Client scripts auto-update from the server bundle (`sudo claude-server deploy-client-bundle`) on connect when a newer version is published.

---

## Tunnel lifetime vs Cursor

The connect process owns the reverse SSH tunnel; Cursor is a separate, longer-lived process. Closing or restarting the connect window must not assume that Cursor has stopped using the remote folder.

Recovery policy:

- Automatic recovery after an unexpected tunnel drop must preserve an editor that is still open on the selected remote folder. It must not run `CLEAR_MOUNT` / `clear_session_mount` while that folder is in use.
- Recovery should re-establish the reverse `-R` forward, validate the existing mount, and only remount after the editor no longer owns the folder or an explicit user disconnect permits cleanup.
- Manual disconnect (`Q` / Enter) may stop the editor and clear the mount. A `finally` / exit handler may keep the `-R` tunnel alive when Cursor still owns the folder; tunnel teardown is not more important than preserving the active editor session.

## One Connect UI per PC

Run **at most one** Claude Connect window per laptop (developer connect, designer, or connect-design). A second launch is refused:

```
[X] Another Claude Connect is already running.
```

| Platform | Mechanism |
|----------|-----------|
| **Windows** | `Global\ClaudeConnect` mutex in `connect-ui.ps1` |
| **Mac** | `flock` on `~/.config/claude-connect/connect.lock` |

Designer Windows and connect-design dot-source the same `connect-ui` helpers as main connect, so they share the lock. Do not run designer and developer connect at the same time.

**Why:** Multiple connect UIs contend for the same reverse `-R` port (`20000 + server UID`). Orphan tunnel cleanup is scoped to stale local `ssh -R` processes and must not kill a peer session (see below).

### Tunnel orphan cleanup (peer safety)

When connect acquires or recovers a tunnel port, `Remove-LocalOrphanTunnel` (Windows) / `remove_local_orphan_tunnel` (Mac) kills **stale** local `ssh -R` forwards only. The live session tunnel PID is always skipped — look for `ORPHAN_TUNNEL: skip_current` in connect logs. Cleanup must never terminate another active connect session on the same port.


## Smart vs Sepidz

One client codebase. Two publish packages (same scripts; different server IP):

| Package | ZIP name | Server IP | README in ZIP |
|---------|----------|-----------|---------------|
| **Smart** | `claude-code-client-YYYYMMDD.zip` | `192.168.210.240` | `README.txt` from `publish/README.txt` |
| **Sepidz** | `claude-code-sepidz-YYYYMMDD.zip` | `192.168.250.70` | `claude-code/README.md` from `publish/README-sepidz.txt` + `designer/` |

Do not mix Smart and Sepidz folders on one laptop for the same workflow - check the IP in the connect header. Logging policy (server-only `~/.claude/logs/`) is identical on both sites.

Publish: `publish\publish.bat` (or `-SmartOnly` / `-SepidzOnly`). Admin: `sudo claude-server deploy-client-bundle` on each server.
## Single project per session

- `ACTIVE_MOUNT` in `~/.claude-connect.conf` names the current project id.
- `claude-mount up <id>` mounts only that project.
- **Other already-mounted projects are not unmounted** on connect.
- On disconnect: **only the current project** is unmounted; `.git` is restored on the laptop.

Project definitions in `~/.claude-mounts.d/<id>.conf` are never deleted when switching projects.

**Mac vs Windows paths:** each mount conf stores a laptop `rpath`. Windows paths (`D:/...`) are purged automatically on Mac connect (and vice versa) so the project list stays usable.

---

## GIT_MODE (OFF / HIDE / SLOW)

| Mode | Behavior |
|------|----------|
| **off** (default) | No `.git` rename on laptop; use `laptop-exec git` on the server for git commands |
| **hide** (HIDE) | Rename `.git` -> `.git.server-session` on laptop before SSHFS (faster mount) |
| **server** (SLOW) | Keep `.git` on SSHFS mount; full git over network (slow) |

| Key | When |
|-----|------|
| `g` | Project menu - toggle mode before session |
| `G` | Active session - toggle + remount |

Config: `~/.config/claude-connect/git.conf` (laptop) pushed to `~/.claude-connect.conf` on server.

If hide fails (Cursor locks `.git`): close Remote SSH / git on laptop, then press `G` to remount.

---

## Session keys

| Key | Action |
|-----|--------|
| `R` | Reconnect tunnel |
| `Q` / Enter | Disconnect (editor down, mount down, restore `.git`) |
| `G` | Change git mode + remount |
| `O` | Relaunch Cursor on correct remote folder |
| `P` | Push Cursor golden auth (bootstrap only) |
| `M` | Project menu after disconnect |
| `C` | Connect again after disconnect |
| `X` | Exit |

---

## Cursor profiles (Windows)

- **Personal:** `%APPDATA%\Cursor` - never touched by connect scripts.
- **Server:** `%LOCALAPPDATA%\ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `cursor-auth-laptop.ps1` merges auth keys into server profile SQLite (never closes Cursor).
- Also writes the Electron profile-root `machineid` / `machineId` files from the server golden identity (login fails if SQLite tokens match but this file drifts).
- Skip path (auth already complete) still heals `machineid`.

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). Correct-folder detection requires the **full remote path** (not only `ssh-remote+alias`).

After auth sync, if Chat still fails: **Developer → Reload Window** in the `[Claude Server]` window. Do **not** sign in with a personal account in that window.

---

## Cursor profiles (Mac)

- **Personal:** `~/Library/Application Support/Cursor` - never touched by connect scripts.
- **Server:** `~/Library/Application Support/ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `git-mode.sh` merges golden auth into server profile `state.vscdb` on each connect (requires `sqlite3`).
- Writes profile-root `machineid` / `machineId` to match `/etc/cursor-auth/golden/machine-id.txt`.
- After auth sync, connect sets `CURSOR_AUTH_RELAUNCH=1` so a long-lived profile process is soft-stopped and relaunched (avoids reusing a weeks-old logged-out window).
- Correct-folder checks require the **full** remote path (e.g. `/home/mohammad/mounts/...`). Matching only `ssh-remote+claude-server` is wrong when several server users share the same SSH alias.

**Remote SSH extension:** install **`anysphere.remote-ssh`** only. Uninstall Microsoft's `ms-vscode-remote.remote-ssh` if present (Extensions → search `@id:anysphere.remote-ssh`).

**Mac socket bug:** profile template sets `"remote.SSH.useLocalServer": false`. If Remote SSH still fails with `listen EINVAL`, run once in Terminal then fully quit Cursor:

```bash
launchctl setenv TMPDIR /tmp
```

Connect also sets `TMPDIR=/tmp` automatically when needed.

If Cursor still asks to log in after sync shows **ok**: fully quit the `[Claude Server]` window (or press **`O`**), do not personal-login into that profile. Reload Window alone is not enough if a stale process held old in-memory auth.

If Cursor opens **Agent home** / wrong user mount path, press **`O`** or reconnect (v20260720.12+).

## Logging

**Policy (v20260720.12+):** zero-loss offline-first. The laptop appends a **durable local day log** and watermark-syncs new bytes to the server when SSH works. `Close-ConnectLog` / `flush_connect_log_to_server` do **not** delete the local day file (offline / failed-SSH sessions stay auditable).

| Where | Path |
|-------|------|
| Laptop Windows (durable day log) | `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` |
| Laptop Mac (durable day log) | `~/.config/claude-connect/logs/connect-YYYYMMDD.log` |
| Server (synced) | `~/.claude/logs/connect-YYYYMMDD.log` |
| Server (SSH diag) | `~/.claude/logs/laptop-ssh-diag-latest.txt` (+ timestamped copies) |

Legacy beside-script `connect.log` / `connect.log.1` are removed on start. Short-lived chunk files under `%TEMP%` / `.chunk` are only staging for scp sync.

**Retention:** server copies under `~/.claude/logs/` older than **1 day** are deleted:

- Client: `find … -mtime +1 -delete` on each sync flush
- Server: `/usr/local/bin/claude-connect-logs-cleanup` via `/etc/cron.d/claude-connect-logs` (hourly, as root)

Local day logs are kept (no automatic wipe on session end).

### What a full log contains (v20260720.12+)

Each connect run uploads a timeline to `~/.claude/logs/connect-YYYYMMDD.log`. Look for these markers in order:

| Marker | Meaning |
|--------|---------|
| `======== session start` | Connect started (version, user, pid) |
| `======== CONTEXT phase=startup` | Early snapshot (host, users, paths) |
| `STEP begin/end` | Named setup steps + duration ms |
| `======== CONTEXT phase=server_ready` | Tunnel port, git mode, server user known |
| `======== CONTEXT phase=project_selected` | Chosen project id + laptop/server paths |
| `SESSION_LOOP begin` + `CONTEXT phase=session_loop` | Mount/auth/editor cycle (reconnect bumps iter) |
| `SSH_BEGIN` / `SSH_END` / `SSH_TIMEOUT` | Every remote `ssh`/`sshx` call |
| `MOUNT` / `PERF[mount_*]` | SSHFS up result + timing |
| `AUTH_*` / `AUTH_SYNC` / `AUTH_REFRESH` / `FOLDER_CHECK` / `LAUNCH_*` | Cursor auth merge, machineid heal, relaunch, folder decisions |
| `STATUS` / `HEARTBEAT` | Live tunnel/editor state while session open |
| `LAPTOP_SSH_DIAG` | Reverse-SSH failure details (also `laptop-ssh-diag-latest.txt`) |
| `RECOVERY_*` | Auto-heal after tunnel drop |
| `======== CONTEXT phase=cleanup` / `session_end` | Disconnect snapshot |
| `======== session end` | Final line of the session (local day log kept) |

`CONTEXT` lines always include: `REMOTE_USER`, `LAPTOP_USER`, `SERVER_IP`, `PORT`, `CONNECT_VERSION`, `GIT_MODE`, `ACTIVE_MOUNT`, editor flags, and `local_cfg` (DEBUG).

**Admin read (on server):**

```bash
sudo-from-laptop cat /home/<user>/.claude/logs/connect-$(date +%Y%m%d).log
sudo-from-laptop cat /home/<user>/.claude/logs/laptop-ssh-diag-latest.txt
```

### Performance marks

`PERF[...]` lines across mount, auth, launch, and diagnostic are opt-in. Enable them for a diagnostic session with:

```
set CLAUDE_CONNECT_PERF_LOG=1
```

Verbose launch diagnostics (WMI snapshots) only when debugging slowness:

```
set CLAUDE_CONNECT_VERBOSE_LAUNCH=1
```

Summarize a **copied** session log on Windows (download from server first, or read the local durable day log under `%USERPROFILE%\.config\claude-connect\logs\`):

```bat
powershell -NoProfile -File scripts\client\tests\parse-connect-perf.ps1 -LogPath path\to\connect-YYYYMMDD.log
```

**Expected gates after Tier A fixes:** cold `Opening Cursor` under 8000 ms, skip path under 1500 ms, `SNAPSHOT` count 0 unless verbose mode.

Useful lines:

```
[INFO]  STEP end: Opening Cursor ok ms=...
[DEBUG] PERF[launch_total] ms=... cim_total=...
[DEBUG] PERF[session_open_summary] ms=0 mount_ms=... auth_ms=... open_ms=... diag_ms=...
[INFO]  LAUNCH_SKIP: already on correct folder - keeping Cursor open
[INFO]  PROJECT: id=...
[INFO]  ACTIVE_MOUNT: ...
[DEBUG] FOLDER_CHECK: on_folder=... agent_home=...
[INFO]  STATUS: [... | Cursor]
```

---

## Mac: Remote Login / reverse SSH

The reverse tunnel needs the **server** to SSH into the Mac as `LAPTOP_USER` (`whoami` short name, e.g. `mohmmad`). That is separate from the **server Linux username** (e.g. `mohammad`).

1. System Settings → Sharing → **Remote Login** = On
2. Allow the Mac account shown by `whoami`, or **All users** (Sharing UI often shows Full Name — allow that row if listed)
3. User must **not** remain only in `com.apple.access_ssh-disabled` (connect heals this from v20260720.12+ / current v20260720.12+: remove from disabled + add to `com.apple.access_ssh`)
4. If key auth still fails, leave connect running until it finishes; diagnostics upload to `~/.claude/logs/laptop-ssh-diag-latest.txt` on the server

Admin password is requested **at most once** per connect run (45s timeout). Destructive Remote Login cycling is skipped when login is already on.

---

## Stale / foreign session heal

If `~/.claude-connect.conf` points at another laptop user but the tunnel port is **not** listening, connect clears the stale conf and continues (avoids “foreign session” dead-ends after a crash or shared account mistake).

---

## Regression tests

```bat
scripts\client\tests\run-all.bat
```

Key tests: `test-connect-pipeline.ps1`, `test-editor-launch-strategies.ps1`, `test-parse-connect-perf.ps1`, `test-git-mode-deep.ps1`, `audit-local-connect.ps1`.

Mac: `scripts/client/tests/verify-all.sh`

---

## Publish / deploy

- Build ZIP on Windows: `publish\publish.bat`
- Client ZIP must not contain `server/` scripts.
- Server mount fix: `sudo claude-server deploy-mount-fix`
- Client auto-update bundle: `sudo claude-server deploy-client-bundle` (requires matching `scripts/client/connect-ui.sh` + `editor-launch.sh` at repo root `scripts/client/`, not under `mac/`)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Join-Path ChildPath prompt | Old `connect.ps1` - copy full `windows\` folder from latest ZIP |
| connect.bat OUTDATED | Missing `connect-ui.ps1` or wrong version in header |
| Cursor Agent home / wrong user path | Update to **v20260720.12+**; press `O`; check `LAUNCH_*` in server log (folder match needs full path) |
| Cursor asks to log in (Mac/Win) after auth **ok** | Quit `[Claude Server]` fully or press `O` (stale process); do not personal-login; confirm `machineid` matches golden |
| Cursor Chat cannot send (Mac/Win) | Reconnect, then **Developer → Reload Window** in `[Claude Server]` window |
| Mac Remote SSH `listen EINVAL` | Update to v20260720.12+; or `launchctl setenv TMPDIR /tmp` + quit Cursor fully |
| Mac Remote SSH timeout | Use `anysphere.remote-ssh` (not Microsoft extension) |
| Laptop SSH key / Permission denied (Mac) | Enable Remote Login; remove user from `access_ssh-disabled`; read `laptop-ssh-diag-latest.txt` on server |
| Empty project list on Mac after Windows session | Auto-adds / purges incompatible `rpath`; add the Mac folder once |
| Stale “foreign session” / wrong LAPTOP_USER | Auto-cleared when tunnel port is down; reconnect |
| No `connect.log` beside bat | Expected — logs are on the server only (v20260720.12+) |
| git hide failed | Close Cursor/git on laptop, press `G` |
| Second connect refused | Close the other connect window first (one UI per PC) |
| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |
| Server path `$HOME/~/...` or leftover `~/` under home | Fixed in v20260720.12+ (`${var#~/}` tilde pitfall); admin may `rm -rf ~/\~` leftover dir |


Questions: contact admin (smart).
