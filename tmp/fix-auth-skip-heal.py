from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')

old = '''    # Skip only when auth is complete AND stamped with the CURRENT golden export.
    # Presence alone is not enough: OAuth rotate every 6h invalidates old pairs.
    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported" 'DEBUG'
        return 0
    fi'''

new = '''    # Skip only when auth is complete AND stamped with the CURRENT golden export.
    # Presence alone is not enough: OAuth rotate every 6h invalidates old pairs.
    # Even on skip, heal Electron machineid file (SQLite-complete profiles can still drift).
    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        write_cursor_profile_machineid || true
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported (machineid healed)" 'DEBUG'
        return 0
    fi'''

if old not in t:
    raise SystemExit('Mac skip block not found')
t = t.replace(old, new, 1)
gm.write_bytes(t.replace('\r\n', '\n').replace('\r', '\n').encode())
print('OK mac skip heal')

# Windows: find AlreadyComplete / skip path
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')
# Find Sync-CursorGoldenAuth or similar skip
lines = pt.splitlines()
for i, l in enumerate(lines):
    if 'AlreadyComplete' in l or 'already_complete' in l or 'Skip' in l and 'Auth' in l:
        print(f'{i+1}:{l}')

# Search Sync-CursorGoldenAuth function
idx = pt.find('function Sync-CursorGoldenAuth')
if idx < 0:
    idx = pt.find('Sync-CursorGoldenAuth')
print('Sync idx', idx)
print(pt[idx:idx+2500][:2500])
