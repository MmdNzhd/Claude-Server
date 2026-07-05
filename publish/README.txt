Claude Code Server - Client Package
=====================================

Current connect scripts: v20260705.4

WINDOWS
-------
1. Copy the extracted folder (claude-code-client-YYYYMMDD) somewhere convenient.
2. Open the windows\ folder.

   Required files (all seven must be in the same folder):
     connect.bat
     connect.ps1
     connect-ui.ps1
     editor-launch.ps1
     git-mode.ps1
     cursor-auth-laptop.ps1
     connect-rider.bat   (optional ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Cursor-only shortcut)

3. Double-click connect.bat.

4. First run: enter server username, add/select project path, enter server
   password once to install the SSH key.

5. Every run after: type a project number (empty Enter does nothing),
   optionally set git mode (g) or IDE (c), Cursor or VS Code opens via Remote SSH.

   Header must show:
     claude-server  |  <server-ip>  |  v20260705.4

   Project menu must include:  g git

   connect-rider.bat ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â same as connect.bat but skips the editor menu (Cursor).

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
     claude-server  |  <server-ip>  |  v20260705.4

   After disconnect: 10s countdown, default M = project menu.

GIT MODE (FAST vs SLOW)
-----------------------
  g  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â in project menu: toggle FAST (hide .git) vs SLOW (full SSHFS git)
  G  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â during active session: change mode and remount

IDE PREFERENCE (c menu)
---------------------
  c  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Configuration: username, IDE (cursor / code / ask), git mode
  ask ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â pick Cursor or VS Code each connect

Preference saved in:
  Windows: %USERPROFILE%\.config\claude-connect\editor.conf
  Mac:     ~/.config/claude-connect/editor.conf

SINGLE PROJECT (important)
--------------------------
  Only ONE project is mounted per session. Requires connect scripts v20260705.4+
  and server-side mount fix (admin deploys from repo ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â not included in this ZIP).

SESSION KEYS
------------
  R  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â reconnect
  Q / Enter ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â disconnect (closes editor, restores .git on laptop)
  G  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â change git mode mid-session
  P  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â push server Cursor login to golden (only when bootstrap banner shown)
  M  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â back to project menu (after disconnect; default after 10s)
  C  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â connect again (after disconnect)
  X  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â exit

TROUBLESHOOTING
---------------
If selecting a project shows "Join-Path ChildPath" prompt:
  - You have an OLD connect.ps1 copy
  - Re-copy the full windows\ folder from this ZIP (all 7 files above)
  - connect.bat blocks outdated folders automatically

If connect.bat says OUTDATED:
  - Missing connect-ui.ps1 or version is not v20260705.4

Do NOT use old folders from previous ZIP dates or stale Desktop copies.

REQUIREMENTS
------------
- Windows 10 or 11 (connect.bat uses PowerShell 5.1)
- macOS 12+ (Monterey or newer)
- Cursor (recommended) or Visual Studio Code
- Remote - SSH extension (built into Cursor; install for VS Code)
- Claude Code extension (server-side ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â configured automatically)
- VPN connection to the company network (for remote work)

TWO CURSOR PROFILES (no conflict)
---------------------------------
  Personal Cursor  ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â open from Start menu / desktop as usual
                     Your login, your settings (%APPDATA%\Cursor)

  Server Cursor    ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â opens ONLY via connect.bat
                     Separate profile (ClaudeServerCursorProfile)
                     Shared server account; title bar shows [Claude Server]
                     Your personal Cursor is never closed or overwritten

  Both can run at the same time. Auth sync never closes any Cursor window ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â it
  merges tokens into the server profile while windows stay open.

Questions? Contact the admin (smart).
