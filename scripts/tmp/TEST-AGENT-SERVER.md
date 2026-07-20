# TEST-AGENT-SERVER — Agent H (mount/watchdog static+syntax)

**Date:** 2026-07-20  
**Agent:** H  
**Project:** `-p claude-code-server`  
**Tunnel:** UP (laptop_os=windows)  
**Scope:** static + `bash -n` only — **no deploy / no remote sudo**

## Verdict: HARD FAIL

| Gate | Result |
|------|--------|
| `bash -n` (all listed scripts) | **PASS** |
| Watchdog restores `.git.server-session` on tunnel down | **HARD FAIL (missing)** |

Overall: **HARD FAIL** (missing git restore on tunnel-down path).

---

## 1. `bash -n` syntax (via laptop-exec + WSL/`bash.exe`)

Bash available: `C:\WINDOWS\system32\bash.exe`

| Script | Exists | `bash -n` |
|--------|--------|-----------|
| `scripts/server/claude-mount.sh` | yes | **OK** |
| `scripts/server/claude-watchdog.sh` | yes | **OK** |
| `scripts/server/claude-automount.sh` | yes | **OK** |
| `scripts/server/commands/add-user.sh` | yes | **OK** |
| `scripts/server/commands/install-client-bundle.sh` | yes | **OK** |

---

## 2. Static HARD checks (`laptop-exec rg` + file read)

### 2.1 Watchdog restores `.git.server-session` on tunnel down — **HARD FAIL**

Evidence:

- `rg '\.git\.server-session' scripts/server/claude-watchdog.sh` → **no matches** (exit 1).
- Tunnel-down branch (`claude-watchdog.sh` ~135–151) only:
  - walks `~/.claude-mounts.d/*.conf`
  - calls `_umount_path` (pkill sshfs + fusermount/umount)
  - `pkill` orphan sshfs under `$HOME/mounts`
  - **`continue`** — no `claude-mount recover`, no `_restore_git`, no rename of `.git.server-session` → `.git`.
- `recover` is only invoked later when tunnel is **UP** (hung non-active ~198; remount ~203).

Contrast: `claude-mount.sh` `_force_unmount_project` **does** call `_restore_git` (rename `.git.server-session` → `.git`), but watchdog bypasses that path and umounts directly — so a tunnel-down event leaves laptop `.git` hidden if `GIT_MODE=hide`.

**Gate rule:** HARD FAIL on missing git restore → **FAIL**.

### 2.2 Mount strips CR from `TUNNEL_PORT` — **FAIL**

| Location | CR strip on conf `TUNNEL_PORT`? |
|----------|----------------------------------|
| `claude-watchdog.sh` `_load_conf` | **YES** — `v="$(printf '%s' "$v" \| tr -d '\r')"` before assign |
| `claude-mount.sh` `_load_global` | **NO** — only quote strip `v="${v#\"}" v="${v%\"}"`; assigns raw `TUNNEL_PORT="$v"` |
| `claude-automount.sh` conf load | **NO** — same as mount |
| `claude-mount.sh` nc probe line | strips `\r\n` from **nc stdout**, not from conf `TUNNEL_PORT` |

CRLF in `~/.claude-connect.conf` can leave `TUNNEL_PORT` with a trailing `\r` for mount/automount.

### 2.3 No first-alphabetical `ACTIVE_MOUNT` write when empty — **FAIL**

When `ACTIVE_MOUNT` is empty:

1. **`claude-automount.sh` ~104–123**
   - Prefer `~/.cache/claude-last-active-mount` (good).
   - Else `for _c in "$CONF_DIR"/*.conf` → first glob hit (bash alphabetical) → **writes** `ACTIVE_MOUNT=` into `~/.claude-connect.conf` via `sed`/`printf`.

2. **`claude-watchdog.sh` `_infer_active` ~74–82 + `_set_active`**
   - Prefer already-mounted project (good).
   - Else first `*.conf` id → `_set_active` **writes** conf + last-active cache.

So empty `ACTIVE_MOUNT` can still persist a first-alphabetical project id.

### 2.4 `install-client-bundle` NOPASSWD scope not world-open — **PASS**

- `install-client-bundle.sh` itself has **no** `NOPASSWD` lines (root-only installer).
- Related sudoers: `scripts/server/sudoers.d/claude-client-deploy` (installed by `install.sh`):
  - `Cmnd_Alias CLAUDE_CLIENT_BUNDLE` = specific bash paths to `install-client-bundle.sh` only
  - `smart` / `sepidz` → `NOPASSWD: CLAUDE_CLIENT_BUNDLE`
  - **Not** `ALL ALL=(ALL) NOPASSWD: ALL` / world-open

---

## 3. Optional PowerShell parse

`[Parser]::ParseFile` on:

| File | Result |
|------|--------|
| `scripts/client/windows/connect.ps1` | OK |
| `scripts/client/connect-ui.ps1` | OK |
| `scripts/client/editor-launch.ps1` | OK |
| `scripts/client/git-mode.ps1` | OK |

---

## Summary table

| Check | Status |
|-------|--------|
| `bash -n` all targets | PASS |
| Watchdog `.git.server-session` restore on tunnel down | **HARD FAIL** |
| Mount strips CR from `TUNNEL_PORT` (conf load) | FAIL |
| No first-alpha `ACTIVE_MOUNT` write when empty | FAIL |
| NOPASSWD not world-open | PASS |
| Optional PS parse | PASS |

## Recommended fixes (not applied — Agent H is read-only)

1. On watchdog tunnel-down: after umount (or before, while tunnel may still flap), invoke `claude-mount recover` / restore path that renames `.git.server-session` → `.git` for affected projects (note: restore currently needs tunnel for laptop SSH — may need best-effort or queue-on-next-up).
2. In `claude-mount.sh` / `claude-automount.sh` conf load: `v="$(printf '%s' "$v" | tr -d '\r')"` like watchdog.
3. Remove alphabetical fallback writes to `ACTIVE_MOUNT` when connect left it empty (infer mount-only or last-active only; do not invent first `*.conf`).
