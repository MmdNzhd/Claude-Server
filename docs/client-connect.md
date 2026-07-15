# Client Connect Guide

Developer and end-user guide for `connect.bat` / `connect.sh`.

**Current client version:** **`20260715.5`**

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

Each `ssh` call opens a new TCP connection (no multiplexing).

---

## Single project per session

- `ACTIVE_MOUNT` in `~/.claude-connect.conf` names the current project id.
- `claude-mount up <id>` mounts only that project.
- **Other already-mounted projects are not unmounted** on connect.
- On disconnect: **only the current project** is unmounted; `.git` is restored on the laptop.

Project definitions in `~/.claude-mounts.d/<id>.conf` are never deleted when switching projects.

---

## GIT_MODE (FAST vs SLOW)

| Mode | Behavior |
|------|----------|
| **hide** (FAST) | Rename `.git` -> `.git.server-session` on laptop before SSHFS; server uses local git mirror |
| **server** (SLOW) | Keep `.git` on SSHFS mount; full git over network |

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

If Cursor opens **Agent home** instead of the project folder, check `connect.log` beside `connect.bat`. v20260715.5+ uses `--new-window` when not on the correct `folder-uri`.

After auth sync, if Chat messages fail: **Developer → Reload Window** in the `[Claude Server]` profile window.

---

## Cursor profiles (Mac)

- **Personal:** `~/Library/Application Support/Cursor` - never touched by connect scripts.
- **Server:** `~/Library/Application Support/ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `git-mode.sh` merges golden auth into server profile `state.vscdb` on each connect (requires `sqlite3`).

**Remote SSH extension:** install **`anysphere.remote-ssh`** only. Uninstall Microsoft's `ms-vscode-remote.remote-ssh` if present (Extensions → search `@id:anysphere.remote-ssh`).

**Mac socket bug:** profile template sets `"remote.SSH.useLocalServer": false`. If Remote SSH still fails with `listen EINVAL`, run once in Terminal then fully quit Cursor:

```bash
launchctl setenv TMPDIR /tmp
```

Connect also sets `TMPDIR=/tmp` automatically when needed.

After auth sync, if Chat messages fail: **Developer → Reload Window** in the `[Claude Server]` profile window.

If Cursor opens **Agent home** instead of the project folder, press **`O`** in the connect menu or reconnect with v20260715.5+.

---

## Logging (Windows)

`connect.log` is written next to `connect.bat`. Rotates at 1.5 MB to `connect.log.1`.

### Performance marks (v20260715.4+)

Cheap `PERF[...]` lines are emitted by default across mount, auth, launch, and diagnostic. Disable with:

```
set CLAUDE_CONNECT_PERF_LOG=0
```

Verbose launch diagnostics (WMI snapshots) only when debugging slowness:

```
set CLAUDE_CONNECT_VERBOSE_LAUNCH=1
```

Summarize a session log on Windows:

```bat
powershell -NoProfile -File scripts\client\tests\parse-connect-perf.ps1 -LogPath connect.log
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
- Server mount fix: `sudo claude-server deploy-mount-fix` (requires connect.bat v20260715.4+)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Join-Path ChildPath prompt | Old `connect.ps1` - copy full `windows\` folder from latest ZIP |
| connect.bat OUTDATED | Missing `connect-ui.ps1` or wrong version in header |
| Cursor Agent home, not project | Update to v20260715.5+, check `connect.log`, press `O` |
| Cursor Chat cannot send (Mac/Win) | Reconnect, then **Developer → Reload Window** in `[Claude Server]` window |
| Mac Remote SSH `listen EINVAL` | Update to v20260715.5+; or `launchctl setenv TMPDIR /tmp` + quit Cursor fully |
| Mac Remote SSH timeout | Use `anysphere.remote-ssh` (not Microsoft extension) |
| git hide failed | Close Cursor/git on laptop, press `G` |
| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |

Questions: contact admin (smart).
