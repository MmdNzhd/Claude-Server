from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')

# ========== docs/client-connect.md ==========
cc = root / 'docs/client-connect.md'
t = cc.read_text(encoding='utf-8')

t = t.replace('**Current client version:** **`20260717.24`**', '**Current client version:** **`20260717.31`**')

# Architecture multiplexing note
old_arch = 'Each `ssh` call opens a new TCP connection (no multiplexing). Client scripts auto-update from the server bundle (`sudo claude-server deploy-client-bundle`) on connect when a newer version is published.'
new_arch = (
    'Windows `ssh` calls are usually separate TCP connections. '
    'Mac `sshx()` reuses one SSH ControlMaster connection for the session (faster setup). '
    'Client scripts auto-update from the server bundle (`sudo claude-server deploy-client-bundle`) on connect when a newer version is published.'
)
if old_arch in t:
    t = t.replace(old_arch, new_arch)
else:
    print('WARN arch mux sentence')

# Expand Windows Cursor profiles auth section
old_win = '''- `cursor-auth-laptop.ps1` merges auth keys into server profile SQLite (never closes Cursor).

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). v20260717.8+ uses `--new-window` when not on the correct `folder-uri`.

After auth sync, if Chat messages fail or Cursor asks to log in: **Developer → Reload Window** in the `[Claude Server]` profile window.
Connect scripts keep the profile `machineid` file aligned with the server golden identity (required for login to stick).'''

new_win = '''- `cursor-auth-laptop.ps1` merges auth keys into server profile SQLite (never closes Cursor).
- Also writes the Electron profile-root `machineid` / `machineId` files from the server golden identity (login fails if SQLite tokens match but this file drifts).
- Skip path (auth already complete) still heals `machineid`.

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). Correct-folder detection requires the **full remote path** (not only `ssh-remote+alias`).

After auth sync, if Chat still fails: **Developer → Reload Window** in the `[Claude Server]` window. Do **not** sign in with a personal account in that window.'''

# Try with unicode arrow variants from file
if old_win not in t:
    # use ascii dump style arrows
    old_win2 = old_win.replace('→', '\u2192')
    if old_win2 in t:
        t = t.replace(old_win2, new_win.replace('→', '\u2192'))
        print('OK win profiles unicode')
    else:
        # fuzzy: replace between markers
        start = t.find('## Cursor profiles (Windows)')
        end = t.find('## Cursor profiles (Mac)')
        if start < 0 or end < 0:
            raise SystemExit('win/mac section markers missing')
        # keep heading, replace body carefully via line surgery later
        print('WARN win exact block; using section replace')
        win_section = '''## Cursor profiles (Windows)

- **Personal:** `%APPDATA%\\Cursor` - never touched by connect scripts.
- **Server:** `%LOCALAPPDATA%\\ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `cursor-auth-laptop.ps1` merges auth keys into server profile SQLite (never closes Cursor).
- Also writes the Electron profile-root `machineid` / `machineId` files from the server golden identity (login fails if SQLite tokens match but this file drifts).
- Skip path (auth already complete) still heals `machineid`.

If Cursor opens **Agent home** instead of the project folder, check the **server** connect log (see [Logging](#logging)). Correct-folder detection requires the **full remote path** (not only `ssh-remote+alias`).

After auth sync, if Chat still fails: **Developer \u2192 Reload Window** in the `[Claude Server]` window. Do **not** sign in with a personal account in that window.

'''
        t = t[:start] + win_section + t[end:]
        print('OK win section replaced')
else:
    t = t.replace(old_win, new_win)
    print('OK win profiles')

# Mac profiles section
start = t.find('## Cursor profiles (Mac)')
end = t.find('## Logging')
if start < 0 or end < 0:
    raise SystemExit('mac/logging markers missing')

mac_section = '''## Cursor profiles (Mac)

- **Personal:** `~/Library/Application Support/Cursor` - never touched by connect scripts.
- **Server:** `~/Library/Application Support/ClaudeServerCursorProfile` via `--user-data-dir`.
- Title bar shows `[Claude Server]` for server profile windows.
- `git-mode.sh` merges golden auth into server profile `state.vscdb` on each connect (requires `sqlite3`).
- Writes profile-root `machineid` / `machineId` to match `/etc/cursor-auth/golden/machine-id.txt`.
- After auth sync, connect sets `CURSOR_AUTH_RELAUNCH=1` so a long-lived profile process is soft-stopped and relaunched (avoids reusing a weeks-old logged-out window).
- Correct-folder checks require the **full** remote path (e.g. `/home/mohammad/mounts/...`). Matching only `ssh-remote+claude-server` is wrong when several server users share the same SSH alias.

**Remote SSH extension:** install **`anysphere.remote-ssh`** only. Uninstall Microsoft's `ms-vscode-remote.remote-ssh` if present (Extensions \u2192 search `@id:anysphere.remote-ssh`).

**Mac socket bug:** profile template sets `"remote.SSH.useLocalServer": false`. If Remote SSH still fails with `listen EINVAL`, run once in Terminal then fully quit Cursor:

```bash
launchctl setenv TMPDIR /tmp
```

Connect also sets `TMPDIR=/tmp` automatically when needed.

If Cursor still asks to log in after sync shows **ok**: fully quit the `[Claude Server]` window (or press **`O`**), do not personal-login into that profile. Reload Window alone is not enough if a stale process held old in-memory auth.

If Cursor opens **Agent home** / wrong user mount path, press **`O`** or reconnect (v20260717.31+).

'''
t = t[:start] + mac_section + t[end:]
print('OK mac section')

# Logging version bumps
t = t.replace('**Policy (v20260717.24+):**', '**Policy (v20260717.31+):**')
t = t.replace('### What a full log contains (v20260717.24+)', '### What a full log contains (v20260717.31+)')
t = t.replace(
    '| Laptop Mac (temp) | `/tmp/claude-connect.*.log` via `mktemp` \u2014 deleted after flush |',
    '| Laptop Mac (temp) | `/tmp/claude-connect.log.XXXXXX` via `mktemp` (XXXXXX must be at end on macOS) \u2014 deleted after flush |'
)
# ascii dash variant
t = t.replace(
    '| Laptop Mac (temp) | `/tmp/claude-connect.*.log` via `mktemp` — deleted after flush |',
    '| Laptop Mac (temp) | `/tmp/claude-connect.log.XXXXXX` via `mktemp` (XXXXXX must be at end on macOS) — deleted after flush |'
)

# Add AUTH markers to log table if not present
if 'AUTH_SYNC' not in t:
    t = t.replace(
        '| `AUTH_*` / `FOLDER_CHECK` / `LAUNCH_*` | Cursor auth + open folder decisions |',
        '| `AUTH_*` / `AUTH_SYNC` / `AUTH_REFRESH` / `FOLDER_CHECK` / `LAUNCH_*` | Cursor auth merge, machineid heal, relaunch, folder decisions |'
    )

# Mac Remote Login - access_ssh-disabled
old_mac_ssh = '''## Mac: Remote Login / reverse SSH

The reverse tunnel needs the **server** to SSH into the Mac as `LAPTOP_USER` (`whoami` short name, e.g. `mohmmad`). That is separate from the **server Linux username** (e.g. `mohammad`).

1. System Settings \u2192 Sharing \u2192 **Remote Login** = On
2. Allow the Mac account shown by `whoami`, or **All users** (Sharing UI often shows Full Name \u2014 allow that row if listed)
3. If key auth still fails, leave connect running until it finishes; diagnostics upload to `~/.claude/logs/laptop-ssh-diag-latest.txt` on the server

Admin password is requested **at most once** per connect run (45s timeout). Destructive Remote Login cycling is skipped when login is already on.'''

mac_ssh = '''## Mac: Remote Login / reverse SSH

The reverse tunnel needs the **server** to SSH into the Mac as `LAPTOP_USER` (`whoami` short name, e.g. `mohmmad`). That is separate from the **server Linux username** (e.g. `mohammad`).

1. System Settings \u2192 Sharing \u2192 **Remote Login** = On
2. Allow the Mac account shown by `whoami`, or **All users** (Sharing UI often shows Full Name — allow that row if listed)
3. User must **not** remain only in `com.apple.access_ssh-disabled` (connect heals this from v20260717.25+: remove from disabled + add to `com.apple.access_ssh`)
4. If key auth still fails, leave connect running until it finishes; diagnostics upload to `~/.claude/logs/laptop-ssh-diag-latest.txt` on the server

Admin password is requested **at most once** per connect run (45s timeout). Destructive Remote Login cycling is skipped when login is already on.'''

# try replace with unicode emdash versions from file
import re
m = re.search(r'## Mac: Remote Login / reverse SSH\n\n.*?\n\n---\n\n## Stale', t, re.S)
if m:
    t = t[:m.start()] + mac_ssh + '\n\n---\n\n## Stale' + t[m.end():]
    print('OK mac ssh section')
else:
    print('WARN mac ssh regex')

# Troubleshooting table updates
troubleshoot_rows = '''| Symptom | Fix |
|---------|-----|
| Join-Path ChildPath prompt | Old `connect.ps1` - copy full `windows\\` folder from latest ZIP |
| connect.bat OUTDATED | Missing `connect-ui.ps1` or wrong version in header |
| Cursor Agent home / wrong user path | Update to **v20260717.31+**; press `O`; check `LAUNCH_*` in server log (folder match needs full path) |
| Cursor asks to log in (Mac/Win) after auth **ok** | Quit `[Claude Server]` fully or press `O` (stale process); do not personal-login; confirm `machineid` matches golden |
| Cursor Chat cannot send (Mac/Win) | Reconnect, then **Developer \u2192 Reload Window** in `[Claude Server]` window |
| Mac Remote SSH `listen EINVAL` | Update to v20260717.31+; or `launchctl setenv TMPDIR /tmp` + quit Cursor fully |
| Mac Remote SSH timeout | Use `anysphere.remote-ssh` (not Microsoft extension) |
| Laptop SSH key / Permission denied (Mac) | Enable Remote Login; remove user from `access_ssh-disabled`; read `laptop-ssh-diag-latest.txt` on server |
| Empty project list on Mac after Windows session | Auto-adds / purges incompatible `rpath`; add the Mac folder once |
| Stale \u201cforeign session\u201d / wrong LAPTOP_USER | Auto-cleared when tunnel port is down; reconnect |
| No `connect.log` beside bat | Expected — logs are on the server only (v20260717.31+) |
| git hide failed | Close Cursor/git on laptop, press `G` |
| Tunnel drops | Auto-reconnect; editor not re-opened on reconnect |'''

m = re.search(r'\| Symptom \| Fix \|.*?\| Tunnel drops \|.*?\n', t, re.S)
if m:
    t = t[:m.start()] + troubleshoot_rows + '\n\n' + t[m.end():]
    # fix double newlines - the Questions line should remain
    print('OK troubleshooting')
else:
    print('WARN troubleshooting')

# Version refs 24 -> 31 remaining in this file
t = t.replace('v20260717.24+', 'v20260717.31+')
t = t.replace('v20260717.24', 'v20260717.31')

cc.write_text(t, encoding='utf-8', newline='\n')
print('wrote client-connect.md')

# ========== CURSOR-AUTH-PILOT.md ==========
pilot = root / 'scripts/server/CURSOR-AUTH-PILOT.md'
p = pilot.read_text(encoding='utf-8')
if 'machineid file' not in p.lower() and 'profile-root machineid' not in p:
    insert = '''
## Laptop profile machineid (v20260717.30+)

Golden tokens in `state.vscdb` are not enough. Electron also reads:

- Mac: `~/Library/Application Support/ClaudeServerCursorProfile/machineid`
- Windows: `%LOCALAPPDATA%\\ClaudeServerCursorProfile\\machineid`

Connect writes these from `/etc/cursor-auth/golden/machine-id.txt` on every merge **and** on the already-complete skip path.

Also require the Cursor window to be on the **correct remote path** for that server user (not another user\\'s mount under the same `claude-server` alias). Mac v20260717.31+ soft-stops the server profile after auth sync so a stale process cannot keep a logged-out session.

'''
    # before Risks section
    if '## Risks' in p:
        p = p.replace('## Risks', insert + '## Risks', 1)
    else:
        p = p + insert
    pilot.write_text(p, encoding='utf-8', newline='\n')
    print('OK pilot')
else:
    print('SKIP pilot')

# ========== CLAUDE.md self-healing ==========
claude = root / 'CLAUDE.md'
c = claude.read_text(encoding='utf-8')
# Update invariant versions already .31
# Add self-heal rows if missing
if 'machineid' not in c.lower() or 'access_ssh-disabled' not in c:
    # find Self-Healing table
    if '| Stale SSHFS mount |' in c and 'machineid' not in c:
        c = c.replace(
            '| Stale SSHFS mount | `claude-mount recover` before each `up` |',
            '| Stale SSHFS mount | `claude-mount recover` before each `up` |\n'
            '| Cursor login despite auth ok (Mac) | Soft-stop server profile after auth; write `machineid`; require full remote path for folder match |\n'
            '| Mac SSH allow-list blocked | Remove user from `com.apple.access_ssh-disabled`; add to `com.apple.access_ssh` |'
        )
        print('OK CLAUDE self-heal rows')
    elif 'machineid' in c.lower():
        print('CLAUDE already mentions machineid')
    else:
        print('WARN CLAUDE self-heal insert')
# Connect logs section version
c = c.replace('v20260717.24', 'v20260717.31')
claude.write_text(c, encoding='utf-8', newline='\n')
print('OK CLAUDE.md')

# ========== README snippets ==========
for rel in ['publish/README.txt', 'publish/README-sepidz.txt']:
    r = root / rel
    txt = r.read_text(encoding='utf-8')
    # ensure version .31
    txt2 = txt.replace('20260717.24', '20260717.31').replace('20260717.30', '20260717.31').replace('20260717.29', '20260717.31')
    if 'machineid' not in txt2.lower():
        # add short AUTH note near LOGS if present
        if 'LOGS (server only' in txt2:
            txt2 = txt2.replace(
                'LOGS (server only',
                'CURSOR AUTH: server golden tokens + profile machineid; use [Claude Server] window only.\n\n'
                'LOGS (server only'
            )
        elif 'LOGS' in txt2:
            pass
    r.write_text(txt2, encoding='utf-8', newline='\n')
    print('OK', rel)

print('DONE')
