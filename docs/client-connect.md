# Client Connect Guide

Developer and end-user guide for `connect.bat` / `connect.sh`.

**Current client version:** **`20260723.13`**

See also: [sshfs-performance.md](sshfs-performance.md) (GIT_MODE deep dive), [CLAUDE.md](../CLAUDE.md) (server admin).

---


## Elevation (Windows)

**elevate-when-needed:** Connect keeps the main UI **unelevated** by default (no UAC on every start).
UAC appears only when `Ensure-LaptopSshReady` / `Invoke-LaptopAdminOps` / `-AdminFix`
must repair sshd, firewall, or `administrators_authorized_keys`.


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

When connect acquires or recovers a tunnel port, `Remove-LocalOrphanTunnel` (Windows) / `remove_local_orphan_tunnel` (Mac) kills **stale** local `ssh -R` forwards only. The live session tunnel PID is always skipped â€” look for `ORPHAN_TUNNEL: skip_current` in connect logs. Cleanup must never terminate another active connect session on the same port.


## Smart vs Sepidz

One client codebase. Two publish packages (same scripts; different server IP):

| Package | ZIP name | Server IP | README in ZIP |
|---------|----------|-----------|---------------|
| **Smart** | `claude-code-client.zip` | `192.168.210.240` | `README.txt` from `publish/README.txt` |
| **Sepidz** | `claude-code-sepidz.zip` | `192.168.250.70` | `claude-code/README.md` from `publish/README-sepidz.txt` + `designer/` |

Do not mix Smart and Sepidz folders on one laptop for the same workflow - check the IP in the connect header. Logging policy (server-only `~/.claude/logs/`) is identical on both sites.

Publish: `publish\publish.bat` (or `-SmartOnly` / `-SepidzOnly`). Admin: `sudo claude-server deploy-client-bundle` on each server.

## Sepidz publish freeze

**Sepidz client publish/deploy is frozen until an explicit user unfreeze.**

- Marker: `publish/SEPIDZ_PUBLISH_FROZEN` (do not delete; do not pass `-ForceUnfreeze` without a direct user ask).
- Sepidz package is **bat-only**: no EXE build, no auto-update from the Smart server bundle.
- Agents must **not** restore server `/usr/local/share/claude-client` while the freeze/`FROZEN` marker is in effect.
- Smart optional update remains separate: policy mode `optional` in `scripts/server/client-update-policy.json` (Quiet = check/log only; never auto-apply).
- **FINAL Desktop artifact:** `C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz` is the frozen snapshot tree. Launchers may be `.DISABLED`; do **not** treat that folder as a live connect package. Do **not** edit it. Smart users: `Desktop\Claude-Connect\` only.
- Marker file also documents this FINAL ARTIFACT stanza (see `publish/SEPIDZ_PUBLISH_FROZEN`).
- Smart user layout: primary install folder `Desktop\Claude-Connect\` (full script tree). Outer `Desktop\Claude-Connect.exe` is a sibling fallback launcher Ã¢â‚¬â€ do not ship Smart users an EXE-only `windows\` strip as the folder package.

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
- **Stamp-first skip:** when local `golden-synced-at.txt` matches server `exported-at` and auth is already complete, connect skips the heavy merge (still heals `machineid` if it drifted).
- After golden token **rotation** (~6h), if the editor stayed open through a stale window, press **`O`** or fully quit `[Claude Server]` â€” Reload Window alone is not enough.

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). Correct-folder detection requires the **full remote path** (not only `ssh-remote+alias`).

After auth sync, if Chat still fails: **Developer â†’ Reload Window** in the `[Claude Server]` window. Do **not** sign in with a personal account in that window.

---

## Cursor profiles (Mac)

- **Personal:** `~/Library/Application Support/Cursor` - never touched by connect scripts.
- **Server:** `~/Library/Application Support/ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `git-mode.sh` merges golden auth into server profile `state.vscdb` on each connect (requires `sqlite3`).
- Writes profile-root `machineid` / `machineId` to match `/etc/cursor-auth/golden/machine-id.txt`.
- After auth sync, connect sets `CURSOR_AUTH_RELAUNCH=1` so a long-lived profile process is soft-stopped and relaunched (avoids reusing a weeks-old logged-out window).
- **Stamp-first skip:** same `golden-synced-at.txt` / `exported-at` stamp match avoids redundant merges when auth is current.
- After golden **rotation**, if Chat fails but logs show auth ok and the editor never relaunched, press **`O`** (or fully quit) â€” do not personal-login into `[Claude Server]`.
- Correct-folder checks require the **full** remote path (e.g. `/home/mohammad/mounts/...`). Matching only `ssh-remote+claude-server` is wrong when several server users share the same SSH alias.

**Remote SSH extension:** install **`anysphere.remote-ssh`** only. Uninstall Microsoft's `ms-vscode-remote.remote-ssh` if present (Extensions â†’ search `@id:anysphere.remote-ssh`).

**Mac socket bug:** profile template sets `"remote.SSH.useLocalServer": false`. If Remote SSH still fails with `listen EINVAL`, run once in Terminal then fully quit Cursor:

```bash
launchctl setenv TMPDIR /tmp
```

Connect also sets `TMPDIR=/tmp` automatically when needed.

If Cursor still asks to log in after sync shows **ok**: fully quit the `[Claude Server]` window (or press **`O`**), do not personal-login into that profile. Reload Window alone is not enough if a stale process held old in-memory auth.

If Cursor opens **Agent home** / wrong user mount path, press **`O`** or reconnect (v20260723.13+).

## Logging

**Policy (v20260723.13+):** zero-loss offline-first. The laptop appends a **durable local day log** and watermark-syncs new bytes to the server when SSH works. `Close-ConnectLog` / `flush_connect_log_to_server` do **not** delete the local day file (offline / failed-SSH sessions stay auditable).

**Console vs file (v20260723.13+):** the day-log *file* always captures every STEP/SESSION_LOOP/TUNNEL_* line (nothing removed - full diagnostics preserved). The *console* is quieter: routine step "ok" lines (`Verifying laptop SSH key`, `Mounting files`, `Syncing Cursor auth`, ...) only paint on the first session-loop pass of a connect. If a tunnel soft-fail silently self-heals on a later pass, that repaint is suppressed - only real failures (`StepFail` / `step_fail`) always stay visible on console, since those drive the R=retry/Q=quit prompts.

| Where | Path |
|-------|------|
| Laptop Windows (durable day log) | `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` |
| Laptop Mac (durable day log) | `~/.config/claude-connect/logs/connect-YYYYMMDD.log` |
| Server (synced) | `~/.claude/logs/connect-YYYYMMDD.log` |
| Server (SSH diag) | `~/.claude/logs/laptop-ssh-diag-latest.txt` (+ timestamped copies) |

Legacy beside-script `connect.log` / `connect.log.1` are removed on start. Short-lived chunk files under `%TEMP%` / `.chunk` are only staging for scp sync.

**Retention:** connect logs older than **1 day** (`mtime +1`) are deleted on both sides:

- Laptop local day logs (`~/.config/claude-connect/logs/`): purged on each connect start (`Clear-ConnectLocalLogsOlderThan` / `find â€¦ -mtime +1`); `sessions.index` is kept
- Server `~/.claude/logs/`: client `find â€¦ -mtime +1 -delete` on each sync flush
- Server cron: `/usr/local/bin/claude-connect-logs-cleanup` via `/etc/cron.d/claude-connect-logs` (hourly, as root)

Session end does **not** delete today's local day file (offline / failed-SSH sessions stay auditable until the next day's retention window).

### What a full log contains (v20260723.13+)

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

### WARN/ERROR sync timing

- **WARN**: local day-log append is immediate; the server-side copy may lag up to **5s** because WARN bursts are coalesced into a single async drain (`Request-ConnectLogSync`) instead of forcing a sync per line.
- **ERROR** and **session-end** (`Wait-ConnectExit`, `Close-ConnectLog`) always call `Complete-ConnectLogAsyncDrain -Force`, which drains any pending WARN backlog *and* force-syncs immediately - no WARN line is ever left stranded on the laptop past session end.
- Watch for `LOG_SYNC_ASYNC scheduled=1` (DEBUG) when a sync has been scheduled but not yet drained; the equivalent Mac helper is `request_connect_log_sync`.

### CONTEXT throttling

- The first `CONTEXT phase=session_loop` on a run is always emitted in full.
- Later reconnect iterations within the same run throttle the repeat snapshot to avoid log spam - look for `CONTEXT skip reason=throttle phase=session_loop iter=N` (DEBUG) instead of the full block. `startup`, `server_ready`, `project_selected`, and `cleanup` phases are never throttled.

### Realistic open-time targets

- ~40s typical cold open, ~35s on a warm laptop (SSHFS/tunnel already primed).
- SSHFS mount itself is **~8-10s irreducible** (SFTP round trips for stat/mkdir) - this floor will not move without changing transport.

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

1. System Settings â†’ Sharing â†’ **Remote Login** = On
2. Allow the Mac account shown by `whoami`, or **All users** (Sharing UI often shows Full Name â€” allow that row if listed)
3. User must **not** remain only in `com.apple.access_ssh-disabled` (connect heals this from v20260723.13+ / current v20260723.13+: remove from disabled + add to `com.apple.access_ssh`)
4. If key auth still fails, leave connect running until it finishes; diagnostics upload to `~/.claude/logs/laptop-ssh-diag-latest.txt` on the server

Admin password is requested **at most once** per connect run (45s timeout). Destructive Remote Login cycling is skipped when login is already on.

---

## Stale / foreign session heal

If `~/.claude-connect.conf` points at another laptop user but the tunnel port is **not** listening, connect clears the stale conf and continues (avoids â€œforeign sessionâ€ dead-ends after a crash or shared account mistake).

---

## Regression tests

```bat
scripts\client\tests\run-all.bat
```

Key tests: `test-connect-pipeline.ps1`, `test-log-sync-contracts.ps1`, `test-error-flush-contract.ps1`, `test-cursor-auth-merge.ps1`, `test-verify-perf-gates.ps1`, `test-parse-connect-perf.ps1`, `audit-local-connect.ps1`.

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
| Cursor Agent home / wrong user path | Update to **v20260723.13+**; press `O`; check `LAUNCH_*` in server log (folder match needs full path) |
| Cursor asks to log in (Mac/Win) after auth **ok** | Quit `[Claude Server]` fully or press `O` (stale process); do not personal-login; confirm `machineid` matches golden |
| Cursor Chat cannot send (Mac/Win) | Reconnect, then **Developer â†’ Reload Window** in `[Claude Server]` window |
| Mac Remote SSH `listen EINVAL` | Update to v20260723.13+; or `launchctl setenv TMPDIR /tmp` + quit Cursor fully |
| Mac Remote SSH timeout | Use `anysphere.remote-ssh` (not Microsoft extension) |
| Laptop SSH key / Permission denied (Mac) | Enable Remote Login; remove user from `access_ssh-disabled`; read `laptop-ssh-diag-latest.txt` on server |
| Empty project list on Mac after Windows session | Auto-adds / purges incompatible `rpath`; add the Mac folder once |
| Stale â€œforeign sessionâ€ / wrong LAPTOP_USER | Auto-cleared when tunnel port is down; reconnect |
| No `connect.log` beside bat | Expected â€” durable day log is `%USERPROFILE%\.config\claude-connect\logs\` (Win) or `~/.config/claude-connect/logs/` (Mac); synced copy at `~/.claude/logs/` |
| git hide failed | Close Cursor/git on laptop, press `G` |
| Second connect refused | Close the other connect window first (one UI per PC) |
| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |
| Server path `$HOME/~/...` or leftover `~/` under home | Fixed in v20260723.13+ (`${var#~/}` tilde pitfall); admin may `rm -rf ~/\~` leftover dir |


## Windows Smart package layout

**Folder / ZIP is primary.** Hand users `Desktop\Claude-Connect\` (full `windows\` script tree: bat + ps1) or the ZIP folder extract. Outer `Desktop\Claude-Connect.exe` is an optional sibling fallback launcher only Ã¢â‚¬â€ do not treat EXE-only as the default handoff.

- Publish keeps the Smart `claude-publish\claude-code-client\windows\` script tree (EXE-only strip is opt-in via `CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY=1`).
- Optional client updates (when the server bundle exists) apply into the folder; Quiet never auto-applies optional updates.
- Server install must never CRLF-strip `*.exe` (`install-client-bundle.sh`). A stripped EXE fails with "not a valid application for this OS platform".

### SmartScreen / Defender false positives (unsigned IExpress EXE)

`Claude-Connect.exe` built by `publish/build-windows-exe.ps1` is an **unsigned IExpress** self-extractor. Windows SmartScreen / Microsoft Defender may show "Windows protected your PC", quarantine, or a cloud false positive on first run Ã¢â‚¬â€ especially for brand-new hashes with no reputation.

**User steps (do not disable Defender):**

1. Prefer the **folder / ZIP** path (`Desktop\Claude-Connect\connect.bat`) Ã¢â‚¬â€ fewer SmartScreen prompts than a cold EXE.
2. If SmartScreen blocks the EXE: **More info Ã¢â€ â€™ Run anyway** (Allow) when you trust the source.
3. If the file is blocked by Mark of the Web (MOTW): right-click Ã¢â€ â€™ Properties Ã¢â€ â€™ **Unblock** Ã¢â€ â€™ OK (or `Unblock-File` in PowerShell on that path only).
4. Optional scoped exclusion **only** for `%USERPROFILE%\Desktop\Claude-Connect` (the install folder). Never exclude the whole Desktop, Downloads, or user profile. Never turn off Microsoft Defender / real-time protection in scripts or docs.
5. Future hardening: sign the published EXE with **Authenticode** (OV code-signing cert + RFC 3161 timestamp) so SmartScreen reputation builds on a stable publisher identity.
6. False-positive remediation: submit the EXE/hash to Microsoft via [WDSI file submission](https://www.microsoft.com/en-us/wdsi/filesubmission) ("Incorrectly detected as malware").

Scripts must **never** disable Defender, SmartScreen, or real-time protection.
## Client auto-update policy

Default mode is **optional forever** (`scripts/server/client-update-policy.json`, `latest` tracks connect version): users can defer (`defer_hours`). Quiet/silent mid-session checks never auto-apply and never log `UPDATE_FORCE` / `applied_ok` unless `mode` is `force` **and** `force_min_version` is set. Smart hard-refuses Sepidz path names (`claude-code-sepidz` / `Claude-Connect-Sepidz`) and Sepidz IP `192.168.250.70` outside a Sepidz tree. Laptop VPN is not a supported Cursor egress path Ã¢â‚¬â€ use Connect xray proxy (PROXY_HEALTH).

