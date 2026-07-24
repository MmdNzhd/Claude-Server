Claude Code Server - Client Package (Smart)
=============================================

Site: Smart
Server IP (baked into connect scripts): 192.168.210.240
Current connect scripts: v20260724.13

WINDOWS
-------

HOW TO GIVE TO OTHERS (Windows)
-------------------------------
**Folder / ZIP is primary** for end users (lowest SmartScreen friction).

1. Run publish\publish.bat on your PC (builds packages; server deploy is optional/admin).
2. Preferred: give users the extracted folder â€” copy `windows\` contents to
   Desktop\Claude-Connect\ (or hand the ZIP and extract there).
3. User double-clicks Desktop\Claude-Connect\connect.bat.
4. Optional fallback: Desktop\Claude-Connect.exe (unsigned IExpress SFX) â€” see
   SmartScreen notes below. Do NOT ship EXE-only as the only handoff.

Option A (folder / ZIP â€” primary):
1. Copy the extracted folder (claude-code-client) or its windows\ tree to
   Desktop\Claude-Connect\.
2. Required files (all must be in the same folder):
     connect.bat
     connect.ps1
     connect-ui.ps1
     editor-launch.ps1
     git-mode.ps1
     cursor-auth-laptop.ps1
     connect-diagnostic.ps1
     connect-rider.bat   (optional - Cursor-only shortcut)
3. Double-click connect.bat.
4. First run: enter server username, add/select project path, enter server
   password once to install the SSH key.
5. Every run after: type a project number (empty Enter does nothing),
   optionally set git mode (g) or IDE (c), Cursor or VS Code opens via Remote SSH.

   Header must show:
     claude-server  |  192.168.210.240  |  v20260724.13

   Project menu must include:  g git

   connect-rider.bat - same as connect.bat but skips the editor menu (Cursor).

Option B (single EXE â€” optional fallback): Desktop\Claude-Connect.exe
  Double-click once. Installs into Desktop\Claude-Connect and launches
  connect.bat. The EXE is an **unsigned IExpress** package and may trip
  SmartScreen / Defender false positives on first run (see below).

SMARTSCREEN / DEFENDER FALSE POSITIVES
--------------------------------------
- Prefer folder/ZIP (Option A). Cold unsigned EXE hashes often lack reputation.
- SmartScreen: More info -> Run anyway (Allow) if you trust the publisher/admin.
- MOTW: right-click file -> Properties -> Unblock (or Unblock-File).
- Scoped exclusion ONLY: %USERPROFILE%\Desktop\Claude-Connect
  (never whole Desktop/Downloads; NEVER disable Microsoft Defender).
- Future: Authenticode sign with OV cert + RFC 3161 timestamp.
- False positive: https://www.microsoft.com/en-us/wdsi/filesubmission
  ("Incorrectly detected as malware").
- Detail: docs/client-connect.md (Windows Smart package layout).

MAC
---
1. Copy the extracted folder somewhere convenient.
2. In Terminal:
       bash mac/connect.sh

   Required files in mac\:
     connect.sh
     git-mode.sh
     connect-ui.sh
     editor-launch.sh
     claude-mount.sh   (auto-pushed to server on connect)

3. Same flow as Windows (project table, git banner, session keys).

   Header must show:
     claude-server  |  192.168.210.240  |  v20260724.13

   After disconnect: 10s countdown, default M = project menu.

   Mac Remote Login: System Settings -> Sharing -> Remote Login must allow
   your Mac account (whoami short name) or All users. That is separate from
   your Linux server username.

GIT MODE (FAST vs SLOW)
-----------------------
  g  - in project menu: toggle FAST (hide .git) vs SLOW (full SSHFS git)
  G  - during active session: change mode and remount

IDE PREFERENCE (c menu)
---------------------
  c  - Configuration: username, IDE (cursor / code / ask), git mode
  ask - pick Cursor or VS Code each connect

Preference saved in:
  Windows: %USERPROFILE%\.config\claude-connect\editor.conf
  Mac:     ~/.config/claude-connect/editor.conf


ONE CONNECT PER PC (important)
------------------------------
  Run only ONE connect.bat / connect.sh window at a time on this laptop.
  A second launch shows: [X] Another Claude Connect is already running.
  Close designer connect before starting developer connect (and vice versa).
  Orphan tunnel cleanup skips the live session ssh -R (peer safety).

SINGLE PROJECT (important)
--------------------------
  Only ONE project is mounted per session. Requires connect scripts v20260724.13+
  and server-side mount fix (admin deploys from repo - not included in this ZIP).

SESSION KEYS
------------
  R  - reconnect
  Q / Enter - disconnect (closes editor, restores .git on laptop)
  G  - change git mode mid-session
  O  - relaunch Cursor on correct remote folder (when status shows agent/closed)
  P  - push server Cursor login to golden (only when bootstrap banner shown)
  M  - back to project menu (after disconnect; default after 10s)
  C  - connect again (after disconnect)
  X  - exit

TROUBLESHOOTING
---------------
If selecting a project shows "Join-Path ChildPath" prompt:
  - You have an OLD connect.ps1 copy
  - Re-copy the full windows\ folder from this ZIP
  - connect.bat blocks outdated folders automatically

If connect.bat says OUTDATED:
  - Missing connect-ui.ps1 or version is not v20260724.13

Do NOT use old folders from previous ZIP dates or stale Desktop copies.
Do NOT mix this Smart package with a Sepidz ZIP (different server IP).

REQUIREMENTS
------------
- Windows 10 or 11 (connect.bat uses PowerShell 5.1)
- macOS 12+ (Monterey or newer)
- Cursor (recommended) or Visual Studio Code
- Remote - SSH extension (built into Cursor; install for VS Code)
- Claude Code extension (server-side - configured automatically)
- VPN connection to the company network (for remote work)

TWO CURSOR PROFILES (no conflict)
---------------------------------
  Personal Cursor - open from Start menu / desktop as usual
                     Your login, your settings (%APPDATA%\Cursor)

  Server Cursor    - opens ONLY via connect.bat
                     Separate profile (ClaudeServerCursorProfile)
                     Shared server account; title bar shows [Claude Server]
                     Your personal Cursor is never closed or overwritten

  Both can run at the same time. Auth sync never closes any Cursor window -
  merges tokens into the server profile while windows stay open.

CURSOR AUTH: server golden tokens + profile machineid; use [Claude Server] window only.

LOGS (durable on laptop + synced to server, v20260724.13+)
------------------------------------------------------------
  Connect keeps a durable local day log on your laptop AND syncs it to the
  server account:

    Laptop: %USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log
    Server: ~/.claude/logs/connect-YYYYMMDD.log
    Server: ~/.claude/logs/laptop-ssh-diag-latest.txt   (after laptop SSH failures)

  WARN lines append locally immediately; the server copy may lag up to 5s
  (coalesced sync). ERROR lines and session end always force-sync right
  away. The laptop copy is never deleted on session end (offline / failed-
  SSH sessions stay auditable); server copies are retained for 1 day
  (hourly cleanup cron).

  Ask admin to read your server logs if Cursor opens Agent home or reverse
  SSH (Mac Remote Login) fails.

Questions? Contact the admin (smart).
