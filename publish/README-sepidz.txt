Claude Code Server - Client Package (Sepidz)
==============================================

Site: Sepidz
Server IP (baked into connect scripts): 192.168.250.70
Current connect scripts: v20260804.16

SEPIDZ PUBLISH FREEZE (permanent until explicit unfreeze)
---------------------------------------------------------
- Marker file: publish\SEPIDZ_PUBLISH_FROZEN - do not delete without a direct user ask.
- Do NOT pass -ForceUnfreeze unless the user explicitly requests unfreeze.
- Sepidz is bat-only: no Claude-Connect EXE, no auto-update from Smart server share.
- Agents must not restore /usr/local/share/claude-client on the server while frozen.
- Keep using connect.bat from claude-code\windows\ (full script folder).

FINAL DESKTOP ARTIFACT (do not treat as live package)
-----------------------------------------------------
Path: C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz
This Desktop tree is the frozen FINAL snapshot. Launchers may be .DISABLED;
do not instruct users/agents to "run connect.bat from that folder" as if live.
Do not edit that tree. Smart users: Desktop\Claude-Connect only.


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
    claude-server  |  192.168.250.70  |  v20260804.16

MAC
  1. In Terminal:
         bash claude-code/mac/connect.sh
  2. Required: connect.sh, git-mode.sh, connect-ui.sh, editor-launch.sh,
     claude-mount.sh

  Header must show:
    claude-server  |  192.168.250.70  |  v20260804.16

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


ONE CONNECT PER PC
------------------
  Run only ONE connect window at a time on this laptop (developer OR designer).
  Second launch: [X] Another Claude Connect is already running.
  Orphan tunnel cleanup never kills the live session ssh -R (peer safety).


SINGLE PROJECT: only one ACTIVE_MOUNT per session (v20260804.16+).

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

LOGS (durable on laptop + synced to server, v20260804.16+)
----------------------------------------------------------------
  Connect keeps a durable local day log on your laptop AND syncs it to
  the Sepidz server account:

    Laptop: %USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log
            ~/.config/claude-connect/logs/connect-YYYYMMDD.log  (Mac)
    Server: ~/.claude/logs/connect-YYYYMMDD.log
    Server: ~/.claude/logs/laptop-ssh-diag-latest.txt   (after laptop SSH failures)

  WARN lines append locally immediately; the server copy may lag up to 5s
  (coalesced sync). ERROR lines and session end always force-sync right
  away. The laptop copy is never deleted on session end; server copies
  are retained for 1 day (hourly cleanup cron).

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
