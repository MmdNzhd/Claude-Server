Claude Code Server - Client Package (Sepidz)
==============================================

Site: Sepidz
Server IP (baked into connect scripts): 192.168.250.70
Current connect scripts: v20260720.1

This ZIP contains two products:

  claude-code\   - Developer connect (Cursor / VS Code Remote SSH)
  designer\      - Designer connect (noVNC only, no editor)

Same client codebase as Smart; only the server IP differs.

DEVELOPER CLIENT (claude-code\)
-------------------------------
WINDOWS
  1. Open claude-code\windows\
  2. Required files in the same folder:
       connect.bat, connect.ps1, connect-ui.ps1, editor-launch.ps1,
       git-mode.ps1, cursor-auth-laptop.ps1, connect-diagnostic.ps1,
       connect-rider.bat (optional)
  3. Double-click connect.bat

  Header must show:
    claude-server  |  192.168.250.70  |  v20260720.1

MAC
  1. In Terminal:
         bash claude-code/mac/connect.sh
  2. Required: connect.sh, git-mode.sh, connect-ui.sh, editor-launch.sh,
     claude-mount.sh

  Header must show:
    claude-server  |  192.168.250.70  |  v20260720.1

  Mac Remote Login: System Settings -> Sharing -> Remote Login must allow
  your Mac account (whoami) or All users. Separate from Linux server username.

GIT MODE / SESSION KEYS (same as Smart)
---------------------------------------
  g / G  - git mode (hide vs slow)
  R      - reconnect
  Q      - disconnect
  O      - relaunch Cursor on project folder
  P      - push Cursor golden auth (bootstrap only)
  M / C / X - menu / reconnect / exit after disconnect

Preference files (laptop):
  Windows: %USERPROFILE%\.config\claude-connect\editor.conf
  Mac:     ~/.config/claude-connect/editor.conf

SINGLE PROJECT: only one ACTIVE_MOUNT per session (v20260720.1+).

DESIGNER CLIENT (designer\)
---------------------------
  Windows: double-click designer\windows\connect.bat
  Mac:     bash designer/mac/connect.sh

  Opens noVNC at http://localhost:27015/vnc.html (no Cursor).
  See designer\README.md for full designer steps.

TROUBLESHOOTING
---------------
  Join-Path ChildPath prompt -> old connect.ps1; re-copy full windows\ folder
  connect.bat OUTDATED      -> missing connect-ui.ps1 or wrong version
  Wrong server / unreachable -> you may have a Smart ZIP (IP 192.168.210.240);
                               use this Sepidz package only
  Do NOT mix Smart and Sepidz folders on the same laptop for the same user
    without knowing which IP is in connect.ps1 / connect.sh

CURSOR AUTH: server golden tokens + profile machineid; use [Claude Server] window only.

LOGS (server only, v20260720.1+)
---------------------------------
  No durable connect.log on the laptop. Logs live on the Sepidz server account:

    ~/.claude/logs/connect-YYYYMMDD.log
    ~/.claude/logs/laptop-ssh-diag-latest.txt

  Temp buffer on laptop (%TEMP% / /tmp) is deleted when connect exits.
  Retention: 1 day on server (hourly cleanup).

REQUIREMENTS
------------
- Windows 10/11 or macOS 12+
- Cursor or VS Code + Remote SSH
- VPN to Sepidz network when off-site

TWO CURSOR PROFILES
-------------------
  Personal Cursor untouched. Server profile (ClaudeServerCursorProfile) opens
  only via connect; title bar shows [Claude Server].

Questions? Contact the admin (smart).
