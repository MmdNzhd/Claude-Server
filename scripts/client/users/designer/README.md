# Designer Connect

SSHFS mount of laptop design folder + noVNC browser desktop. No Cursor/VS Code.

Client scripts: **v20260726.10** (Windows developer package uses same git-mode modules).

Ships in the **Sepidz** ZIP under `designer/` (IP `192.168.250.70`). Smart developer ZIPs do not include designer.

## Windows

Required files (same folder):

| File |
|------|
| `connect.bat` |
| `connect.ps1` |
| `git-mode.ps1` |

1. Double-click `connect.bat`
2. First time: enter server username + laptop folder path (`-Setup` to change later)
3. Browser opens noVNC: `http://localhost:27015/vnc.html`

**Git mode:** preference in `%USERPROFILE%\.config\claude-connect-designer\git.conf`

| Key | Action |
|-----|--------|
| `G` | Change git mode + remount (`laptop` mount id) |
| `R` | Reconnect |
| `Q` | Disconnect |

Default: **hide**

**Reconfigure path:** `connect.bat -Setup`

---

## Mac

Required: `connect.sh` + `git-mode.sh`

```bash
bash connect.sh
bash connect.sh --setup
```

Same hotkeys (`G`, `R`, `Q`).

EXIT / SIGTERM / **SIGHUP** traps clean up the server mount when the Terminal closes.

---


## One Connect UI per PC

Run **one** connect window at a time on the laptop. Windows designer uses the same `Enter-ConnectSingleInstance` lock as developer connect (via `connect-ui.ps1`). Do not run designer and developer connect together â€” the second launch shows `[X] Another Claude Connect is already running.`

## What This Does

- Reverse SSH tunnel â†’ server
- SSHFS: server `/home/designer/mounts/laptop`
- SSH local forward: laptop `127.0.0.1:27015` (noVNC binds localhost only)
- Chrome on server downloads to mounted laptop folder (managed policy)

---

## Server (Admin)

```bash
sudo claude-server install
sudo designer-start start    # VNC stack for designer user
```

Designer Chrome download dir: `/home/designer/mounts/laptop` (via managed policy).

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| noVNC not reachable | Admin: `sudo designer-start start` on server |
| Mount fails | Check laptop path with `-Setup`; ensure OpenSSH Server / Remote Login |
| Git hide warning | `G` to remount after closing Cursor/git on laptop |
| Wrong site IP | Use Sepidz package (`192.168.250.70`), not Smart (`192.168.210.240`) |

Sepidz package uses the same connect scripts as Smart; publish patches only the server IP.

See [docs/client-connect.md](../../../../docs/client-connect.md) for developer connect (logs, GIT_MODE, Smart vs Sepidz).
