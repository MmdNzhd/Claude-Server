from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')

# Mac: on skip, heal from local SQLite (no extra SSH)
gm = root / 'scripts/client/git-mode.sh'
t = gm.read_text(encoding='utf-8')
old = '''    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        write_cursor_profile_machineid || true
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported (machineid healed)" 'DEBUG'
        return 0
    fi'''
new = '''    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        # Prefer local SQLite machine id (already golden); fall back to server file.
        _skip_mid="$(sqlite3 "$db" "SELECT value FROM ItemTable WHERE key='storage.serviceMachineId' LIMIT 1;" 2>/dev/null | tr -d '\\r\\n' || true)"
        write_cursor_profile_machineid "${_skip_mid:-}" || true
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported (machineid healed)" 'DEBUG'
        return 0
    fi'''
if old not in t:
    raise SystemExit('mac skip not found')
t = t.replace(old, new, 1)
gm.write_bytes(t.replace('\r\n','\n').replace('\r','\n').encode())
print('OK mac skip from db')

# Windows: heal from SQLite map instead of scp when possible
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')
old = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        # Heal Electron machineid even when SQLite auth is already complete.
        $midHeal = $null
        try {
            $goldMidFile = Join-Path $env:TEMP ("claude-golden-machine-id-" + [guid]::NewGuid().ToString('N') + ".txt")
            scp -o BatchMode=yes -o ConnectTimeout=10 -q "${Alias}:/etc/cursor-auth/golden/machine-id.txt" $goldMidFile 2>$null
            if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $goldMidFile)) {
                $midHeal = (Get-Content -LiteralPath $goldMidFile -Raw -ErrorAction SilentlyContinue).Trim()
            }
            Remove-Item -LiteralPath $goldMidFile -Force -ErrorAction SilentlyContinue
        } catch { }
        if ($midHeal) { Write-CursorProfileMachineId -MachineId $midHeal | Out-Null }'''

new = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        # Heal Electron machineid even when SQLite auth is already complete.
        $midHeal = $null
        try {
            if (Initialize-CursorAuthSqlite) {
                $midHeal = [CursorAuthSqlite]::GetValue($dbPath, 'storage.serviceMachineId')
            }
        } catch { }
        if (-not $midHeal) {
            try {
                $goldMidFile = Join-Path $env:TEMP ("claude-golden-machine-id-" + [guid]::NewGuid().ToString('N') + ".txt")
                scp -o BatchMode=yes -o ConnectTimeout=10 -q "${Alias}:/etc/cursor-auth/golden/machine-id.txt" $goldMidFile 2>$null
                if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $goldMidFile)) {
                    $midHeal = (Get-Content -LiteralPath $goldMidFile -Raw -ErrorAction SilentlyContinue).Trim()
                }
                Remove-Item -LiteralPath $goldMidFile -Force -ErrorAction SilentlyContinue
            } catch { }
        }
        if ($midHeal) { Write-CursorProfileMachineId -MachineId $midHeal | Out-Null }'''

if old not in pt:
    raise SystemExit('win skip not found for replace')
pt = pt.replace(old, new, 1)

# Does GetValue exist?
if 'GetValue' not in pt and 'static string GetValue' not in pt:
    # use HasNonEmptyValue pattern - search how values are read
    if '::GetValue' in new:
        # Check CursorAuthSqlite class for methods
        import re
        methods = re.findall(r'public static[^{]+', pt)
        print('methods sample:', methods[:15])
        # Prefer reading via a known API - look for GetString or similar
        for m in ['GetValue', 'ReadValue', 'GetAuthValue', 'QueryValue']:
            if m in pt:
                print('found', m)

# Safer: don't call GetValue if missing - use python/sqlite via existing helper
# Search for how other code reads a key
idx = pt.find('class CursorAuthSqlite')
print(pt[idx:idx+2000][:2000])

ps.write_text(pt, encoding='utf-8', newline='\n')
print('wrote win - verify GetValue')
