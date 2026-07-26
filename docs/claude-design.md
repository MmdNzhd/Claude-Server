# Claude Design — Complete Guide

> **Difference from Designer Connect:** This document covers `connect-design.bat` (claude.ai/design in shared server Chrome). For laptop folder mount + noVNC see [`users/designer/README.md`](../scripts/client/users/designer/README.md) and [`docs/client-connect.md`](client-connect.md).

## What is it?

Claude Design is a shared browser environment on the server that lets designers connect to claude.ai/design using the server fingerprint (not their own laptop). One shared Chrome session runs on the server that all designers connect to.

## Architecture

```
Windows (laptop)
  └─ connect-design.bat / connect-design.ps1
       ├─ SSH → designer@server  →  designer-start start W H
       │                              ├─ Xvfb :UID  (virtual display — 4K max)
       │                              ├─ x11vnc      (VNC server)
       │                              ├─ websockify  (WebSocket bridge)
       │                              └─ Chrome      (claude.ai/design) ← never closed
       └─ SSH Tunnel  localhost:6080 → server:NOVNC_PORT
            └─ Edge/Chrome  →  noVNC  →  VNC  →  Chrome on server
```

## Shared user

All designers connect as user **`designer`**. Only one person can work at a time. If a second person connects, the first is **kicked** and receives a message. The first person can press R to reclaim the session.

## Port mapping

| Service | Port |
|-------|------|
| VNC | 25000 + UID |
| noVNC / websockify | 26000 + UID |
| SSH tunnel (client) | 6080 (fixed) |

## Initial server install (once)

```bash
sudo claude-server add-user designer --no-password-change
sudo claude-server install    # designer deps + Chrome policy (idempotent)
```

## Adding a new designer SSH key

```bash
sudo claude-server add-user designer   # or append key to designer ~/.ssh/authorized_keys
```

## Connecting from Windows

Required files (same folder):
- `scripts/client/windows/connect-design.bat`
- `scripts/client/windows/connect-design.ps1`

Double-click `connect-design.bat` — everything runs automatically.

## First connection (login)

Chrome opens on the server. **Once** log in to claude.ai. After that the session is saved for all designers.

To exit kiosk mode: `Alt+F4` — then run the bat again.

## Chrome behavior

- Chrome on the server is **never** closed (even when nobody is connected)
- When a designer connects, they see the same existing Chrome instance
- Session, tabs, and login are always preserved
- Chrome profile is stored in `/opt/chrome-design-profile` (shared by everyone)

## Resolution behavior

- `connect-design.ps1` reads the primary monitor size
- Xvfb starts at maximum size (4K)
- `xrandr` sets resolution to the actual monitor size — without restarting Chrome
- If xrandr fails, only Xvfb/x11vnc/websockify restart (not Chrome)

## Kick mechanism

When designer B connects while A is connected:
1. B sees **"Previous user was disconnected"**
2. A's websockify is killed → A's tunnel drops
3. A sees **"You were disconnected by another designer"**
4. A can press R to reclaim the session (which kicks B)
5. Chrome on the server stays **running** through all of this

## noVNC settings

```
http://localhost:6080/vnc.html?autoconnect=true&resize=none&quality=9&compression=0&reconnect=true&reconnect_delay=2000&view_only=0
```

| Parameter | Value | Description |
|---------|-------|-------|
| resize | none | No scaling |
| quality | 9 | Highest quality |
| compression | 0 | No compression (internal network) |
| reconnect | true | Auto-reconnect inside browser |
| reconnect_delay | 2000 | Retry every 2 seconds |
| view_only | 0 | Mouse and keyboard active |

## Updating designer-start

After any change to `scripts/server/designer-start.sh`:

```bash
sudo install -m 755 /home/smart/mounts/claude-code-server/scripts/server/designer-start.sh /usr/local/bin/designer-start
```

## Server management with claude-server CLI

```bash
# Install on a new server (once)
git clone <repo> && sudo bash scripts/server/claude-server install

# Add a new developer
sudo claude-server add-user <username>

# Verify health of all components
claude-server verify

# Active sessions + usage + token cost
claude-server status

# Help
claude-server --help
```

## Admin commands (on server)

```bash
# Session status
sudo -u designer designer-start status

# Full stop (Chrome closes too)
sudo -u designer designer-start stop

# Manual start with specific resolution
sudo -u designer designer-start start 1920 1080

# Check processes
ps aux | grep designer | grep -E "Xvfb|x11vnc|websockify|chrome" | grep -v grep

# Session log
tail -f /home/designer/.designer/session.log

# Add SSH key
echo "ssh-ed25519 AAAA..." >> /home/designer/.ssh/authorized_keys
```

## Chrome rendering (SwiftShader)

Because the server has no physical GPU, Chrome uses software rendering. Required flags in `designer-start.sh`:

```bash
--use-gl=angle
--use-angle=swiftshader-webgl
--enable-unsafe-swiftshader
```

**Note:** The old flag `--use-gl=swiftshader` is deprecated from Chrome 130 onward and fully removed in Chrome 139. Using it removes ANGLE from the graphics pipeline and WebGL will not work.

## Troubleshooting

### Chat box does not open / design page does not load
Permission problem on Chrome profile or `.local/share`:
```bash
# Signs in log:
# Failed to open persistent cache files ... Permission denied
# ContextResult::kTransientFailure: Failed to send GpuControl.CreateCommandBuffer

sudo chown -R designer:designer /opt/chrome-design-profile
sudo chmod -R 755 /opt/chrome-design-profile
sudo mkdir -p /home/designer/.local/share
sudo chown -R designer:designer /home/designer/.local
designer-start stop && designer-start start 1920 1080
```

### "ERROR: another start in progress"
A lock file was left behind. Remove it:
```bash
rm -f /home/designer/.designer/start.lock
```

### noVNC keeps reconnecting
x11vnc or websockify crashed:
```bash
pkill -u designer x11vnc; pkill -u designer websockify
sudo -u designer designer-start start 1920 1080
```

### Chrome opened a new profile
Singleton lock left behind:
```bash
rm -f /opt/chrome-design-profile/SingletonLock /opt/chrome-design-profile/SingletonSocket /opt/chrome-design-profile/SingletonCookie
```

### Black screen
x11vnc did not start:
```bash
pkill -u designer x11vnc
sudo -u designer designer-start start 1920 1080
```

### SSH key not accepted
```bash
sudo claude-server add-user designer
# then add laptop pubkey to designer ~/.ssh/authorized_keys
```

### Server host key changed
The PowerShell script handles this automatically. If manual fix is needed:
```powershell
ssh-keygen -R 192.168.210.240
```

## Disk space

- Chrome profile: `/opt/chrome-design-profile` (shared)
- Session log: `/home/designer/.designer/session.log` (keeps max 500KB)
- RAM per session: roughly 200-400MB
