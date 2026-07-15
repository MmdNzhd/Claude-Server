# Designer Connect

SSHFS mount of laptop design folder + noVNC browser desktop. No Cursor/VS Code.

Client scripts: **v20260715.15** (Windows developer package uses same git-mode modules).

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

---

## What This Does

- Reverse SSH tunnel: server
- SSHFS: server `/home/designer/mounts/laptop`
- SSH local forward: laptop `127.0.0.1:27015`
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
| Mount fails | Check laptop path with `-Setup`; ensure OpenSSH Server running |
| Git hide warning | `G` to remount after closing Cursor/git on laptop |

Sepidz package uses the same connect scripts; publish patches only the server IP.

See [docs/client-connect.md](../../../../docs/client-connect.md) for GIT_MODE details.
