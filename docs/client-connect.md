# Client Connect Guide

Developer and end-user guide for `connect.bat` / `connect.sh`.

**Current client version:** **`20260802.4`**

See also: [sshfs-performance.md](sshfs-performance.md) (GIT_MODE deep dive), [CLAUDE.md](../CLAUDE.md) (server admin).

**Quick links:** [Windows console hide](#windows-console-hide-no-flash)  [Smart package / handoff](#windows-smart-package-layout)  [Auto-update policy](#client-auto-update-policy)

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

When connect acquires or recovers a tunnel port, `Remove-LocalOrphanTunnel` (Windows) / `remove_local_orphan_tunnel` (Mac) kills **stale** local `ssh -R` forwards only. The live session tunnel PID is always skipped - look for `ORPHAN_TUNNEL: skip_current` in connect logs. Cleanup must never terminate another active connect session on the same port.


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
- Smart user layout: primary install folder `Desktop\Claude-Connect\` (full script tree).
- Smart handoff artifacts live under `Desktop\claude-publish\` (`claude-code-client.zip`, `Claude-Connect-VERSION.exe`, alias `Claude-Connect.exe`). Do not leave unversioned `Desktop\Claude-Connect.exe` on the Desktop root after publish.
- Do not ship Smart users an EXE-only `windows\` strip as the folder package.

## Windows console hide (no flash)

**Policy (v20260802.4+):** helper `cmd` / PowerShell windows must not be visible (taskbar or desktop). `start /MIN` is **forbidden** - minimized consoles still appear on the taskbar.

### Why this exists

Older Connect used `start /MIN` and helper `powershell` without outer `-WindowStyle Hidden`. Users saw flash/orphan consoles titled like `Claude Connect` even when the real UI later opened. True hide requires `WScript.Shell.Run` style **0** (hidden), not minimize.

### Launch paths (best -> fallback)

| Path | What runs | Visible? |
|---|---|---|
| **Best** | `Desktop\Claude-Connect\Claude-Connect.vbs` -> `connect-hide-relaunch.vbs` -> hidden `connect.bat` INNER -> `start` visible `connect-boot.ps1` UI | Only the Connect UI console |
| Good | `Claude-Connect.cmd` = direct `wscript //B //Nologo ...vbs` (written by `connect-update` / publish setup-launch) | Same as VBS |
| OK | Double-click `connect.bat` (OUTER): self-relaunch via hide VBS, then INNER continues | Brief OUTER may flash under Explorer; INNER hidden |
| Fallback | If `connect-hide-relaunch.vbs` missing: `Start-Process ... -WindowStyle Hidden` + belt script | Still no `/MIN` |

### Files and roles

| File | Role |
|---|---|
| `windows/connect-hide-relaunch.vbs` | Sets `CLAUDE_CONNECT_BAT_INNER=1`, runs `cmd /c connect.bat` with `WshShell.Run ..., 0, False` |
| `windows/connect-hide-console.ps1` | Belt: `GetConsoleWindow` + `ShowWindow(SW_HIDE)`; swallows all errors (`2>nul` / fail-open) |
| `windows/connect.bat` | OUTER -> VBS relaunch; INNER calls hide-console belt; every helper `powershell` uses `-WindowStyle Hidden`; **final** UI is `start "" powershell ... connect-boot.ps1` (visible on purpose) |
| `windows/connect-boot.ps1` | Root stub also prefers hide-relaunch VBS when redirecting into a versioned `src\` tree |
| `windows/connect-update.ps1` | Instant launcher rewrite; bat self-relaunch uses `Start-Process -WindowStyle Hidden` |
| `publish/_setup-launch-body.ps1` | Same instant-launcher contract at publish time |

### Ship / deploy lists (must stay in sync)

Hide helpers must appear in **all** of:

- `publish/publish.ps1` copy list + IExpress stage
- `publish/client-bundle-manifest.tsv` (`win` rows)
- `scripts/server/commands/deploy-client-bundle.sh` (laptop-exec stage paths + `win_files`)
- Heal/bootstrap copy lists inside `connect.bat` / `connect-bootstrap.ps1` / `connect-heal.ps1`

Never publish a Windows tree that has `connect.bat` but lacks the two hide helpers.

### Known edge cases

| Case | Behavior |
|---|---|
| Path with spaces | Supported; VBS/`Start-Process` must use one quoted argument string (array `ArgumentList` can mangle paths) |
| Path with `()` parentheses | `connect.bat` preflight can break; **VBS path still hide-safe** - prefer `.vbs` / `.cmd` trampoline |
| Unicode path (non-ASCII) | `findstr` OUTDATED guards in bat can fail (false OUTDATED); VBS/cmd trampoline still usable; prefer PowerShell version checks long-term |
| Missing hide-console.ps1 | Fail-open; INNER must still not leave a titled visible helper |
| Throwing hide-console.ps1 | Fail-open (`2>nul`); boot must continue |
| Do **not** pass `-WindowStyle Hidden` to `wscript.exe` itself | Can suppress child `WshShell.Run` windows incorrectly on some hosts |

### Verify after install / share

1. Header shows current version (e.g. `v20260802.4`).
2. Folder contains `connect-hide-relaunch.vbs` + `connect-hide-console.ps1`.
3. `Claude-Connect.cmd` has **no** `start` and **no** `/MIN`; calls `wscript` directly.
4. Launch via `.vbs`: no lasting helper `cmd` titled `Claude Connect` on the taskbar (only the UI window).
5. Regression: `powershell -File scripts\client\tests\test-harder-live-console-hide-storm.ps1` (wired in `run-all.ps1` as `harder-live-console-hide-storm`).

### What to give others (Smart)

| Give | Path | Extra files needed? |
|---|---|---|
| ZIP (lowest SmartScreen friction) | `Desktop\claude-publish\claude-code-client.zip` | No - extract `windows\` -> `Desktop\Claude-Connect\` |
| Single EXE | `Desktop\claude-publish\Claude-Connect-VERSION.exe` (alias `Claude-Connect.exe`) | **No** - SFX includes hide helpers |
| Daily shortcut | `Desktop\Claude-Connect\Claude-Connect.vbs` | Already next to `connect.bat` after install |

Always hand the **latest** publish after `publish\publish.bat` (or `-SmartOnly`). Do not share stale `Claude-Connect-Setup.exe.old-*` or an older dated EXE. Sepidz uses a different ZIP/EXE (frozen; different IP) - never mix.

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

Git mode UI (`g` / `G` / project-menu `3`) is removed; site policy forces **off**. `Configure-GitMode` may remain as a dead helper with no menu path.

Config: `~/.config/claude-connect/git.conf` (laptop) pushed to `~/.claude-connect.conf` on server.

If hide fails (Cursor locks `.git`): close Remote SSH / git on laptop, then reconnect (`R`).

---

## Session keys

| Key | Action |
|-----|--------|
| `R` | Reconnect tunnel |
| `Q` / Enter | Disconnect (editor down, mount down, restore `.git`) |
| `H` | Hygiene: scan stale multi-Connect leftovers -> soft-clean orphans/idle -> optional second confirm to close sibling Connect tunnels, sibling Connect windows, and that sibling's Cursor project window only (never personal Cursor or the current project window) |
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
- After golden token **rotation** (~6h), if the editor stayed open through a stale window, press **`O`** or fully quit `[Claude Server]` - Reload Window alone is not enough.

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). Correct-folder detection requires the **full remote path** (not only `ssh-remote+alias`).

After auth sync, if Chat still fails: **Developer -> Reload Window** in the `[Claude Server]` window. Do **not** sign in with a personal account in that window.

---

## Cursor profiles (Mac)

- **Personal:** `~/Library/Application Support/Cursor` - never touched by connect scripts.
- **Server:** `~/Library/Application Support/ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `git-mode.sh` merges golden auth into server profile `state.vscdb` on each connect (requires `sqlite3`).
- Writes profile-root `machineid` / `machineId` to match `/etc/cursor-auth/golden/machine-id.txt`.
- After auth sync, connect sets `CURSOR_AUTH_RELAUNCH=1` so a long-lived profile process is soft-stopped and relaunched (avoids reusing a weeks-old logged-out window).
- **Stamp-first skip:** same `golden-synced-at.txt` / `exported-at` stamp match avoids redundant merges when auth is current.
- After golden **rotation**, if Chat fails but logs show auth ok and the editor never relaunched, press **`O`** (or fully quit) - do not personal-login into `[Claude Server]`.
- Correct-folder checks require the **full** remote path (e.g. `/home/mohammad/mounts/...`). Matching only `ssh-remote+claude-server` is wrong when several server users share the same SSH alias.

**Remote SSH extension:** install **`anysphere.remote-ssh`** only. Uninstall Microsoft's `ms-vscode-remote.remote-ssh` if present (Extensions -> search `@id:anysphere.remote-ssh`).

**Mac socket bug:** profile template sets `"remote.SSH.useLocalServer": false`. If Remote SSH still fails with `listen EINVAL`, run once in Terminal then fully quit Cursor:

```bash
launchctl setenv TMPDIR /tmp
```

Connect also sets `TMPDIR=/tmp` automatically when needed.

If Cursor still asks to log in after sync shows **ok**: fully quit the `[Claude Server]` window (or press **`O`**), do not personal-login into that profile. Reload Window alone is not enough if a stale process held old in-memory auth.

If Cursor opens **Agent home** / wrong user mount path, press **`O`** or reconnect (v20260802.4+).

## Logging

**Policy (v20260802.4+):** zero-loss offline-first. The laptop appends a **durable local day log** and watermark-syncs new bytes to the server when SSH works. `Close-ConnectLog` / `flush_connect_log_to_server` do **not** delete the local day file (offline / failed-SSH sessions stay auditable).

**Console vs file (v20260802.4+):** the day-log *file* always captures every STEP/SESSION_LOOP/TUNNEL_* line (nothing removed - full diagnostics preserved). The *console* is quieter: routine step "ok" lines (`Verifying laptop SSH key`, `Mounting files`, `Syncing Cursor auth`, ...) only paint on the first session-loop pass of a connect. If a tunnel soft-fail silently self-heals on a later pass, that repaint is suppressed - only real failures (`StepFail` / `step_fail`) always stay visible on console, since those drive the R=retry/Q=quit prompts.

| Where | Path |
|-------|------|
| Laptop Windows (durable day log) | `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` |
| Laptop Mac (durable day log) | `~/.config/claude-connect/logs/connect-YYYYMMDD.log` |
| Server (synced) | `~/.claude/logs/connect-YYYYMMDD.log` |
| Server (SSH diag) | `~/.claude/logs/laptop-ssh-diag-latest.txt` (+ timestamped copies) |

Legacy beside-script `connect.log` / `connect.log.1` are removed on start. Short-lived chunk files under `%TEMP%` / `.chunk` are only staging for scp sync.

**Retention:** connect logs older than **1 day** (`mtime +1`) are deleted on both sides:

- Laptop local day logs (`~/.config/claude-connect/logs/`): purged on each connect start (`Clear-ConnectLocalLogsOlderThan` / `find ... -mtime +1`); `sessions.index` is kept
- Server `~/.claude/logs/`: client `find ... -mtime +1 -delete` on each sync flush
- Server cron: `/usr/local/bin/claude-connect-logs-cleanup` via `/etc/cron.d/claude-connect-logs` (hourly, as root)

Session end does **not** delete today's local day file (offline / failed-SSH sessions stay auditable until the next day's retention window).

### What a full log contains (v20260802.4+)

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
| `MOUNT_CHECK_SKIPPED` / `MOUNT_BG_*` | BG mount path (skip sync check; child BEGIN/OK/FAIL) |
| `SCORECARD` | Auth/mount/editor summary; `editor=` from `$script:EditorOpened`; also `port=` / optional `conf_port=` + `agent_path=` |
| `AGENT_PATH` | Every ~60s: server `TUNNEL_PORT` vs this UI port + listen checks. `ok` even when dual-UI `session!=conf` if conf port listens; `bad` only for `conf_empty` / `conf_port_closed` / `probe_fail` |
| `SSH_ROLLUP` | Every ~60s: SSH latency min/p50/p90/max + `over_2s` / `over_5s` (diagnose slow Cursor without reading every `SSH_END`) |
| `PUSH_CONF signal=` | WARN when PushConf emits `ABORT_EMPTY` / `port_empty_recovered` / `port_mismatch_keep` |
| `LAPTOP_EXEC ... meaning=aborted` | Tool/parent SIGTERM/INT/HUP: LE killed `timeout`/`ssh` tree and released mux slot |
| `AUTH_*` / `AUTH_SYNC` / `AUTH_REFRESH` / `FOLDER_CHECK` / `LAUNCH_*` | Cursor auth merge, machineid heal, relaunch, folder decisions |
| `AUTH_SYNC_SKIP ... db_too_large` | Laptop `state.vscdb` > 500 MiB - mid-session auth merge skipped (chat cache bloat) |
| `STATUS` / `HEARTBEAT` | Live tunnel/editor state while session open |
| `LAPTOP_SSH_DIAG` | Reverse-SSH failure details (also `laptop-ssh-diag-latest.txt`) |
| `RECOVERY_*` | Auto-heal after tunnel drop |
| `======== CONTEXT phase=cleanup` / `session_end` | Disconnect snapshot |
| `======== session end` | Final line of the session (local day log kept) |

#### Zombie-owner / reseed Gap markers (v20260802.4+)

When diagnosing dual-Connect / sticky reverse-port issues, look for these exact reason tokens (identical on Windows and Mac):

| Marker | Meaning |
|--------|---------|
| `ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind` | Gap: ReseedRaw true but another Connect-shaped owner holds Claim - keep existing `-R`, do not kill for proxy reseed |
| `ENSURE_TUNNEL bg_init_reseed_skip reason=foreign_owner_cannot_bind` | Windows bg_init cleared `needReseed` under the same Gap (Win only; Mac goes through ensure) |
| `TUNNEL_WAIT ok=0` / `fail=1` `reason=local_r_not_owned` | Banner/TCP looked up but spawn pid is not in local `-R` SSH PIDs - Wait must not report success |
| `ENSURE_TUNNEL refuse_spawn reason=stale_port_busy` | After `port still busy` within 15s and no local `-R`, Ensure refuses spawn on that port (or rebinds) |
| `CURSOR_PROXY_OWNER: released reason=service_dead` | Claimed owner + backends down + xray expected for >=60s - lease released |
| `CURSOR_PROXY_OWNER: adopt stale_non_connect` | Claim adopted a live PID that is not Connect-shaped (stale sidecar/ssh) |
| `TUNNEL_SYNC soft_fail_exhausted_zombie_drop` | After >=120s continuous no_proc keep-alive with auth/banner failure - drop (first budget exhaust still keep-alives) |

Healthy single-window path should still log `proxy_leg=-L` when xray is up. A Gap skip must **not** be followed by `killing stale bg` for that proxy reseed.

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


### Mount background path (v20260802.4+)

When `GIT_MODE` is not `off` and the project is not already a healthy skip-remount, Windows Connect **does not** run a synchronous `claude-mount check` on the critical path. It logs `MOUNT_CHECK_SKIPPED reason=bg_up`, starts SSHFS `up` in a background job, paints **Mounting files** as StepOk `started in background`, and continues to Opening Cursor.

| Marker | Meaning |
|--------|---------|
| `MOUNT_CHECK_SKIPPED reason=bg_up` | Sync mount health check skipped because BG `up` was kicked |
| `MOUNT_BG_STARTED` | Parent spawned the background mount runner (pid) |
| `MOUNT_BG_BEGIN` | Child began `claude-mount up` |
| `MOUNT_BG_OK` / `MOUNT_BG_FAIL` | Child finished success or failure (same day log; grep session id) |

`GIT_MODE=off` and the healthy `skip_remount` path still use the sync/skip-remount contracts (no BG skip). Agents use `laptop-exec` / Windows-MCP; SSHFS is for the Cursor tree only and may lag until `MOUNT_BG_OK`.

### MountOk pending vs StepOk

- **UI StepOk** for BG mount may show `started in background` (user-facing progress).
- **`$mountOk` / SCORECARD / `SESSION_OPEN -MountOk`** stay **false** while `Out=started_in_background` / `Pending=true` until live remount evidence (`MOUNT_BG_OK` observed or a healthy re-probe / `skip_remount`).
- Do not treat StepOk paint as MountOk=true.

### SCORECARD / EditorOpened (script scope)

`Write-ConnectScorecard` prefers **`$script:EditorOpened`** (wired by `connect.ps1`). Scope-local `$editorOpened` is secondary. **`$script:EditorSeenOpen` alone must not** OR into SCORECARD `editor=` (sticky SeenOpen caused false-green). After a failed Opening Cursor step, sticky flags clear when no window is still proven open (`EDITOR_SEEN_CLEAR reason=opening_step_fail`).

### Cursor launch console detach

Windows Cursor launch uses `DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP` (and related no-attach env) so the Connect console does **not** inherit Cursor Chromium `[main]` / COPUpdater spam. GUI still shows (`SW_SHOW`).

### Log sync: fast mkdir + Needed restore

- Fast / non-Force sync SSH runs **mkdir + chmod only** ," **no** `find -mtime +1` on that path (retention `find` runs on Force / rebuild paths).
- `Complete-ConnectLogAsyncDrain -Force`: if the force sync fails, **`ConnectLogSyncNeeded` is restored to true** (no silent clear of Needed). Watch `LOG_SYNC_OK` / `LOG_SYNC_FAIL` / `LOG_SYNC_ASYNC scheduled=1`.

### Mac / Designer parity notes

- Mac `clear_session_mount` calls `release_cursor_proxy_owner` so disconnect releases the Cursor proxy claim.
- Designer Windows `connect.ps1` calls `Close-ConnectLog` on exit paths so day-log drain/sync matches main Connect.

### Before / after acceptance table (fill after live measure)

Do **not** invent a "3x faster" claim. Use measured STEP/SCORECARD/SSH counts from day logs. Stage-2 baseline evidence (Smart laptop, 2026-07-25 plan) for **before** columns only:

| Metric | Before (cite day log / Stage-2) | After (v20260802.4 measure) | Notes |
|--------|----------------------------------|------------------------------|-------|
| Mounting files median (success) | ~46 ms (Jul 25 BG UI) / ~15467 ms (Jul 24 sync) | _TBD ms_ | BG path should stay near-instant in UI |
| Sync `claude-mount check` after pick (BG path) | present (pre-Task-1) | _expect 0_ `SSH_BEGIN ... check` | Look for `MOUNT_CHECK_SKIPPED` |
| `MOUNT_BG_BEGIN` / `OK` / `FAIL` in day log | 0 body events (Jul 25 silence) | _count_ | Child must share mutex path |
| Opening Cursor fail rate | 68.4% (13/19 Jul 25) | _%_ | Target below Jul 25 rate |
| SCORECARD `editor=` vs visible Cursor | false-green risk | _match / mismatch_ | Uses `$script:EditorOpened` |
| `SESSION_OPEN` MountOk while BG pending | was optimistic true | _expect false until OK_ | |
| `LOG_SYNC_OK` per session end | 0 (Jul 25) | _count / Needed retry_ | Needed must not silent-clear on Force fail |

### Acceptance checklist (plan Task 11)

Fresh connect, pick project, then confirm in the local day log:

1. [ ] No `SSH_BEGIN ... claude-mount check` between project pick and Opening Cursor on the BG path
2. [ ] `MOUNT_BG_BEGIN` then `MOUNT_BG_OK` or `MOUNT_BG_FAIL` in the same day log
3. [ ] SCORECARD `editor=` matches visible Cursor window state
4. [ ] `SESSION_OPEN` MountOk false while mount pending; true after BG OK or skipRemount
5. [ ] `LOG_SYNC_OK` at least once at session end, or Needed remains true with retry (not silent clear)
6. [ ] Opening Cursor fail rate measured on the new day log (report; target below Jul 25 68%)

Publish: bump is ready in-tree; run `publish\publish.bat` only when shipping the client ZIP (not part of this docs slice).

---

## Mac: Remote Login / reverse SSH

The reverse tunnel needs the **server** to SSH into the Mac as `LAPTOP_USER` (`whoami` short name, e.g. `mohmmad`). That is separate from the **server Linux username** (e.g. `mohammad`).

1. System Settings -> Sharing -> **Remote Login** = On
2. Allow the Mac account shown by `whoami`, or **All users** (Sharing UI often shows Full Name - allow that row if listed)
3. User must **not** remain only in `com.apple.access_ssh-disabled` (connect heals this from v20260802.4+: remove from disabled + add to `com.apple.access_ssh`)
4. If key auth still fails, leave connect running until it finishes; diagnostics upload to `~/.claude/logs/laptop-ssh-diag-latest.txt` on the server

Admin password is requested **at most once** per connect run (45s timeout). Destructive Remote Login cycling is skipped when login is already on.

---

## Stale / foreign session heal

If `~/.claude-connect.conf` points at another laptop user but the tunnel port is **not** listening, connect clears the stale conf and continues (avoids "foreign session" dead-ends after a crash or shared account mistake).

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
| Cursor Agent home / wrong user path | Update to **v20260802.4+**; press `O`; check `LAUNCH_*` in server log (folder match needs full path) |
| Cursor asks to log in (Mac/Win) after auth **ok** | Quit `[Claude Server]` fully or press `O` (stale process); do not personal-login; confirm `machineid` matches golden |
| Cursor Chat cannot send (Mac/Win) | Reconnect, then **Developer -> Reload Window** in `[Claude Server]` window |
| Mac Remote SSH `listen EINVAL` | Update to v20260802.4+; or `launchctl setenv TMPDIR /tmp` + quit Cursor fully |
| Mac Remote SSH timeout | Use `anysphere.remote-ssh` (not Microsoft extension) |
| Laptop SSH key / Permission denied (Mac) | Enable Remote Login; remove user from `access_ssh-disabled`; read `laptop-ssh-diag-latest.txt` on server |
| Empty project list on Mac after Windows session | Auto-adds / purges incompatible `rpath`; add the Mac folder once |
| Stale s..."foreign session" / wrong LAPTOP_USER | Auto-cleared when tunnel port is down; reconnect |
| No `connect.log` beside bat | Expected - durable day log is `%USERPROFILE%\.config\claude-connect\logs\` (Win) or `~/.config/claude-connect/logs/` (Mac); synced copy at `~/.claude/logs/` |
| git hide failed | Close Cursor/git on laptop, press `G` |
| Second connect refused | Close the other connect window first (one UI per PC) |
| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |
| Server path `$HOME/~/...` or leftover `~/` under home | Fixed in v20260802.4+ (`${var#~/}` tilde pitfall); admin may `rm -rf ~/\~` leftover dir |
| `AUTH_SYNC_SKIP db_too_large` / Cursor UI very slow | Chat cache in `%LOCALAPPDATA%\ClaudeServerCursorProfile-*\User\globalStorage\state.vscdb` > 500 MiB. **Close** `[Claude Server]` Cursor, then from repo: `powershell -File scripts\client\cursor-profile-db-tool.ps1 -PruneChatAgent -Force`. Reopen connect. (Manual only - not auto-wired into connect.) |
| Agents Stop but `dotnet`/build keep running | Fixed in laptop-exec abort trap (TERM/INT kills `timeout`/`ssh` tree + `CMD_END meaning=aborted`). Redeploy: `sudo claude-server deploy-laptop-exec` / install. |
| Many old `extensionHost` / `server-main` on server | Hourly `cursor-server-reaper --apply` (idle, age1h, no TCP clients). Dry-run: `cursor-server-reaper --user YOU`. Log: `/var/log/cursor-server-reaper.log`. |


## Windows Smart package layout

**Give the latest publish only** (after `publish\publish.bat` / `-SmartOnly`).

| Handoff | Path | Notes |
|---|---|---|
| ZIP (preferred) | `Desktop\claude-publish\claude-code-client.zip` | Extract `windows\` -> `Desktop\Claude-Connect\`; run `connect.bat` |
| Single EXE | `Desktop\claude-publish\Claude-Connect-VERSION.exe` (alias `Claude-Connect.exe`) | One file is enough; SFX installs the full tree including hide helpers |
| Daily use | `Desktop\Claude-Connect\Claude-Connect.vbs` (or `connect.bat`) | Prefer `.vbs` for zero Explorer cmd flash |

- Publish keeps the Smart `claude-publish\claude-code-client\windows\` script tree (EXE-only strip is opt-in via `CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY=1`).
- Required Windows tree includes `connect-hide-relaunch.vbs` + `connect-hide-console.ps1` (also listed in `publish/client-bundle-manifest.tsv`).
- Optional client updates (when the server bundle exists) apply into the folder; Quiet never auto-applies optional updates.
- Server install must never CRLF-strip `*.exe` (`install-client-bundle.sh`). A stripped EXE fails with "not a valid application for this OS platform".
- Do not share stale Desktop `Claude-Connect-Setup.exe.old-*` backups or an old dated EXE from a previous publish.

### SmartScreen / Defender false positives (unsigned IExpress EXE)

`Claude-Connect.exe` built by `publish/build-windows-exe.ps1` is an **unsigned IExpress** self-extractor. Windows SmartScreen / Microsoft Defender may show "Windows protected your PC", quarantine, or a cloud false positive on first run - especially for brand-new hashes with no reputation.

**User steps (do not disable Defender):**

1. Prefer the **folder / ZIP** path (`Desktop\Claude-Connect\connect.bat`) - fewer SmartScreen prompts than a cold EXE.
2. If SmartScreen blocks the EXE: **More info -> Run anyway** (Allow) when you trust the source.
3. If the file is blocked by Mark of the Web (MOTW): right-click -> Properties -> **Unblock** -> OK (or `Unblock-File` in PowerShell on that path only).
4. Optional scoped exclusion **only** for `%USERPROFILE%\Desktop\Claude-Connect` (the install folder). Never exclude the whole Desktop, Downloads, or user profile. Never turn off Microsoft Defender / real-time protection in scripts or docs.
5. Future hardening: sign the published EXE with **Authenticode** (OV code-signing cert + RFC 3161 timestamp) so SmartScreen reputation builds on a stable publisher identity.
6. False-positive remediation: submit the EXE/hash to Microsoft via [WDSI file submission](https://www.microsoft.com/en-us/wdsi/filesubmission) ("Incorrectly detected as malware").

Scripts must **never** disable Defender, SmartScreen, or real-time protection.
## Client auto-update policy

Default mode is **optional forever** (`scripts/server/client-update-policy.json`, `latest` tracks connect version): users can defer (`defer_hours`). Quiet/silent mid-session checks never auto-apply and never log `UPDATE_FORCE` / `applied_ok` unless `mode` is `force` **and** `force_min_version` is set. Smart hard-refuses Sepidz path names (`claude-code-sepidz` / `Claude-Connect-Sepidz`) and Sepidz IP `192.168.250.70` outside a Sepidz tree. Laptop VPN is not a supported Cursor egress path ',,," use Connect xray proxy (PROXY_HEALTH).


