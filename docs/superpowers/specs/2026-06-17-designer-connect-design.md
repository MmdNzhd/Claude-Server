# Designer Connect Scripts — Design Spec

**Date:** 2026-06-17
**Status:** Approved

---

## Overview

Two connect scripts (Mac `.sh` + Windows `.ps1`) for the `designer` Linux user.
When run, they SSHFS-mount the designer's laptop folder to `/home/designer/work/` on the server
and forward noVNC (port 27015) locally so the designer can open Chrome via browser.

---

## Architecture

```
Designer Laptop ──SSH──▶ Server (port 22)
Server ──SSHFS──▶ Designer Laptop (via reverse tunnel on port 20000+UID)
                  mounts at /home/designer/work/
Laptop browser ──localhost:27015──▶ (SSH local forward) ──▶ server 127.0.0.1:27015 (noVNC)
```

---

## Files

```
scripts/client/users/designer/connect.sh     # Mac/Linux launcher
scripts/client/users/designer/connect.ps1    # Windows launcher
```

---

## Key Differences from Developer Scripts

| Aspect | Developer scripts | Designer scripts |
|---|---|---|
| Server username | Configurable (asked on first run) | Hardcoded `designer` |
| Project picker | Full add/edit/delete UI | Auto-create `laptop` mount on first run, no picker |
| After mount | Open VS Code / Rider | Open `http://localhost:27015/vnc.html` in browser |
| Editor opened flag | `_editor_opened` / `$editorOpened` | `_novnc_opened` / `$novncOpened` — set **only on success**; retries on reconnect if noVNC was unreachable |
| SSH tunnel flags | `-R PORT:localhost:22` | `-R PORT:localhost:22 -L 127.0.0.1:27015:127.0.0.1:27015` |
| Signal traps (bash) | EXIT + SIGTERM | EXIT + SIGTERM + **SIGHUP** (terminal close) |
| Auto-fix retry guard | None needed (one-shot) | `$autoFixCount` cap 3; reset on manual R reconnect, NOT on auto-reconnect `continue` |

---

## SSH Tunnel

The tunnel adds a local port forward alongside the reverse tunnel:

```bash
ssh -N \
  -o ExitOnForwardFailure=no \
  -o ServerAliveInterval=20 \
  -o ServerAliveCountMax=5 \
  -R "$PORT:localhost:22" \
  -L "27015:127.0.0.1:27015" \
  "$ALIAS"
```

`ExitOnForwardFailure=no` — if port 27015 is already in use on the laptop, the tunnel still comes up
(SSHFS works); only the noVNC forward silently fails. Script checks noVNC reachability after mount.

---

## Project / Mount

On first run the script auto-creates a `laptop` mount entry via `claude-mount add`:

- **id:** `laptop`
- **label:** `Laptop`
- **rpath:** the path the designer provides (e.g. `/Users/sara/designs` or `D:/designs`)
- **lpath:** `/home/designer/work/laptop`

On subsequent runs it skips the prompt and mounts `laptop` directly (no picker shown).
Designer can re-run with `--setup` flag to reconfigure the path.

---

## noVNC Flow

After mount succeeds:

1. Check if noVNC port forward is reachable: `nc -zw2 localhost 27015` (Mac) / `TcpClient` (Windows)
2. If reachable and `_novnc_opened == 0`:
   - Mac: `open "http://localhost:27015/vnc.html"`
   - Windows: `Start-Process "http://localhost:27015/vnc.html"`
   - Set `_novnc_opened=1` **only here** (inside the success branch) — do NOT re-open on reconnect
3. If not reachable: warn, show `http://SERVER_IP:27015/vnc.html` fallback, leave `_novnc_opened=0` so reconnect retries
   (works if on same LAN; fails if remote/VPN-only)

---

## Self-Healing (inherited from developer scripts)

All the following behaviors are preserved identically:

| Problem | Auto-fix |
|---|---|
| SSH key rejected | Reinstall `claude_laptop.pub` into `authorized_keys`, retry |
| Windows sshd stopped | `Start-Service sshd` with up-to-20s readiness wait |
| Windows firewall SSH rule missing | `New-NetFirewallRule` / `Enable-NetFirewallRule` |
| Stale SSHFS mount | `claude-mount recover` before each `up` |
| Tunnel drops during session | Auto-reconnect loop; noVNC not re-opened on reconnect |
| SSH permission errors (Windows) | `icacls` fixes on `.ssh/`, `authorized_keys`, `config` |
| Connection reset | Kill zombie sshfs on server, restart sshd |
| sshd restart kills tunnel | Re-check tunnel before retry mount |

---

## Edge Cases

1. **noVNC localhost-only** — websockify binds `127.0.0.1:27015`, not `0.0.0.0`. Must use SSH local forward.
2. **Port 27015 conflict on laptop** — `ExitOnForwardFailure=no` keeps tunnel alive; warn user noVNC may not open.
3. **VNC stack not running on server** — noVNC check fails; print hint: `ssh smart@SERVER sudo designer-start start`.
4. **Zombie tunnel (bash, no job control)** — Mac: `ps -o state=` zombie filter on `_tunnel_alive()`.
5. **Persian/Arabic keyboard** — Windows: `[ConsoleKey]::R/Q/C/X` physical key checks alongside `KeyChar`.
6. **Double cleanup guard** — `already_down` / `$alreadyDown` prevents duplicate `claude-mount down` on EXIT+SIGTERM+SIGHUP.
7. **Single-quote sanitization** — paths through `tr "'" '-'` (bash) / `-replace "'"` (PS) before remote shell.
8. **`--setup` flag** — re-run first-time setup (reconfigure laptop path) without losing SSH config.
9. **Config validation** — both `LAPTOP_USER` and `LAPTOP_PATH` validated non-empty after conf source; clear `die`/`Die` if missing (catches hand-edited conf).
10. **Auto-fix infinite loop guard** — Windows: `$autoFixCount` (cap 3) prevents infinite sshd-restart loop on persistent mount failures; reset to 0 on manual R reconnect.
11. **Q pressed while tunnel dies (Windows)** — key buffer drained before defaulting to auto-reconnect; Q/Enter honored even when tunnel exits simultaneously.
12. **`$SshDir` ACL (Windows)** — when `$LaptopUser != $env:USERNAME`, both the admin user AND `$LaptopUser` are granted `(OI)(CI)F` on the `.ssh` directory; without this, Windows sshd cannot read `authorized_keys` under the target user's token.
13. **ERE pipe in grep** — `grep -E "^${MOUNT_ID}\|"` uses explicit ERE with escaped `\|`; avoids breakage when `grep` is aliased to `grep -E`.

---

## Session UI

```
    Designer Connect
    claude-server  |  192.168.210.240

    Laptop SSH Server ................. ok
    Laptop SSH key .................... ok
    Server config ..................... designer
    Tunnel port + server key .......... port 21015
    Server key ........................ ok
    Configuring server ................ laptop=sara port=21015
    Ready

    Mounting files .................... 2.1s
      -> /home/designer/work/laptop
    Opening noVNC ..................... http://localhost:27015/vnc.html

    ============================================
    Session active -- keep this window open
    R = reconnect   Q or Enter = disconnect
    ============================================
```

---

## Constraints

- No Persian text in scripts (CLAUDE.md rule).
- Must follow all CLAUDE.md client script invariants (port formula, single-quote sanitization, etc.).
- Server username `designer` is hardcoded — no first-time username prompt.
- `CM='$HOME/.local/bin/claude-mount'` single-quoted so `$HOME` expands on remote shell.
