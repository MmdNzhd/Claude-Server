# Designer Connect — Quick Start

## Windows

1. Copy `connect.bat` + `connect.ps1` to your laptop
2. Double-click `connect.bat`
3. First time: enter your server username and the path to your design files on this laptop
4. Browser opens automatically with the remote desktop (noVNC)

**Reconnect:** press `R` in the connect window  
**Disconnect:** press `Q` or close the window  
**Reconfigure:** `connect.bat -Setup`

---

## Mac

```bash
bash connect.sh
```

Same flow as Windows. Browser opens automatically with the remote desktop.

**Reconfigure:** `bash connect.sh --setup`

---

## What This Does

- Mounts your laptop's design folder on the server so design tools and files are accessible remotely
- Opens a browser-based remote desktop (noVNC) connected to the server
- All changes save directly to your laptop
