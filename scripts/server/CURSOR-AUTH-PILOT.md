# Cursor Golden Auth — Pilot Validation

Run this checklist on the server **after** bootstrap and before rolling out to all developers.

## Prerequisites

1. Deploy scripts: `sudo claude-server install`
2. Bootstrap login on server (pick one):
   - `agent login` as a developer user, **or**
   - connect once via Cursor Remote SSH from a laptop
3. Export golden identity (pick one):
   - **Recommended:** connect from laptop, sign in to the **server account** inside the blue `[Claude Server]` window only (never personal Cursor), press **P** in connect.bat to push golden to server
   - **Or on server:** after a full Cursor IDE login (not `agent login` alone):
   ```bash
   sudo cursor-auth-export --from-user smart
   sudo claude-server sync-cursor-auth
   ```

## Automated checks

```bash
sudo claude-server diagnose-auth    # Cursor golden auth section should be green
sudo claude-server verify           # machineId matches golden for synced users
sudo claude-server sync-cursor-auth # idempotent re-sync
```

Expected:
- `/etc/cursor-auth/golden/auth.json` exists with access + refresh tokens (file mode 0600, dir 0700)
- `/etc/cursor-auth/golden/state-keys.json` exists (full SQLite key map for sync)
- `/etc/cursor-auth/golden/machine-id.txt` non-empty
- Each developer `~/.config/Cursor/User/globalStorage/state.vscdb` has matching `storage.serviceMachineId`

## Manual pilot (user smart)

1. `sudo claude-server sync-cursor-auth smart`
2. On laptop: run `connect.bat` from folder with all seven Windows files (`connect.ps1`, `connect-ui.ps1`, `editor-launch.ps1`, `git-mode.ps1`, `cursor-auth-laptop.ps1`); header must show `v20260703.12`
3. In Cursor: open **Chat** and **Composer** — must work **without** laptop Cursor login
4. Run `Developer: Reload Window` once after first sync if session was already open

## Multi-user / multi-laptop test

1. `sudo claude-server sync-cursor-auth amir` (second developer)
2. Connect from **a different laptop** as amir
3. Confirm Chat/Composer works without separate login
4. Run diagnose-auth — both users show **machineId matches golden**

## Token refresh

```bash
sudo cursor-auth-refresh
tail -3 /var/log/cursor-auth-refresh.log
sudo claude-server diagnose-auth
```

## Failure actions

| Symptom | Fix |
|---------|-----|
| Cursor asks to log in on laptop | `sudo claude-server sync-cursor-auth <user>`, reload window |
| machineId drift | `sudo claude-server sync-cursor-auth` |
| refresh failed / shouldLogout | Re-login once, `sudo cursor-auth-export --from-user <name>`, sync all |
| golden bundle missing | Complete step 2–3 in Prerequisites |


## Laptop profile machineid (v20260717.32+)

Golden tokens in `state.vscdb` are not enough. Electron also reads:

- Mac: `~/Library/Application Support/ClaudeServerCursorProfile/machineid`
- Windows: `%LOCALAPPDATA%\ClaudeServerCursorProfile\machineid`

Connect writes these from `/etc/cursor-auth/golden/machine-id.txt` on every merge **and** on the already-complete skip path.

Also require the Cursor window to be on the **correct remote path** for that server user (not another user\'s mount under the same `claude-server` alias). Mac v20260717.32+ soft-stops the server profile after auth sync so a stale process cannot keep a logged-out session.

## Risks (not testable locally)

- Cursor may flag concurrent sessions or shared-account usage (see CLAUDE.md)
- Official multi-developer path: Cursor Teams/Enterprise with per-seat billing
