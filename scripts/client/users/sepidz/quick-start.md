# Claude Code Server — Quick Start

## Server Management

### Add a user
```bash
sudo claude-server add-user <username>
# With no forced password change:
sudo claude-server add-user <username> --no-password-change
```

### Set / change password
```bash
passwd <username>
```

### Check everything is healthy
```bash
claude-server verify
```

### Active sessions + usage stats
```bash
claude-server status
```

### Re-run install (after updates)
```bash
sudo claude-server install
```

---

## Auth Token (one time per server)

On a laptop with browser:
```bash
claude setup-token
```

On server as root:
```bash
echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' > /etc/profile.d/claude-auth.sh
chmod 644 /etc/profile.d/claude-auth.sh
echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> /etc/environment
```

---

## Client (Windows)

1. Copy `connect.bat` + `connect.ps1` to laptop
2. Double-click `connect.bat`
3. First time: enter server username
4. Select or add a project folder
5. If both Cursor and VS Code are installed, choose which editor to open
6. Editor opens — run `claude` in the terminal

**Reconnect:** press `R` in the connect window  
**Disconnect:** press `Q` or close the window  
**After disconnect:** press `C` to reconnect or `X` to exit

**Reconfigure username:** `connect.bat -Setup`

---

## Client (Mac)

```bash
bash connect.sh
```

Same flow as Windows. If both Cursor and VS Code are installed, the script will ask which editor to use.

**Reconfigure username:** `bash connect.sh --setup`
