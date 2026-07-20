from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')

# Simplify skip heal block if messy
old = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        # Heal Electron machineid even when SQLite auth is already complete.
        $midHeal = $null
        try {
            $midPath = Join-Path (Split-Path $localGs -Parent | Split-Path -Parent) 'machineid'
            # Profile root is parent of User/globalStorage -> User -> profile
            $profileDir = Get-CursorRemoteProfileDir
            $goldMidFile = Join-Path $env:TEMP 'claude-golden-machine-id.txt'
            scp -o BatchMode=yes -o ConnectTimeout=10 -q "${Alias}:/etc/cursor-auth/golden/machine-id.txt" $goldMidFile 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $goldMidFile)) {
                $midHeal = (Get-Content $goldMidFile -Raw -ErrorAction SilentlyContinue).Trim()
                Remove-Item $goldMidFile -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        if ($midHeal) { Write-CursorProfileMachineId -MachineId $midHeal | Out-Null }'''

new = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
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

if old not in pt:
    # maybe already different - check
    if 'machineid healed' in pt:
        print('skip block present, checking style')
        idx = pt.find('machineid healed')
        print(pt[idx-700:idx+100])
    else:
        raise SystemExit('skip heal block missing')
else:
    pt = pt.replace(old, new, 1)
    print('OK simplified skip heal')

# Add machineid mismatch to Test-CursorAuthNeedsRefresh after serviceMachineId check
needle = '''    try {
        if (-not [CursorAuthSqlite]::HasNonEmptyValue($DbPath, 'storage.serviceMachineId')) {
            $reasons += 'serviceMachineId_empty'
        }
    } catch {
        $reasons += 'serviceMachineId_check_failed'
    }

    $personalMain = 0'''

insert = '''    try {
        if (-not [CursorAuthSqlite]::HasNonEmptyValue($DbPath, 'storage.serviceMachineId')) {
            $reasons += 'serviceMachineId_empty'
        }
    } catch {
        $reasons += 'serviceMachineId_check_failed'
    }

    try {
        $profileDir = Get-CursorRemoteProfileDir
        $fileMid = ''
        $midFile = Join-Path $profileDir 'machineid'
        if (Test-Path -LiteralPath $midFile) {
            $fileMid = (Get-Content -LiteralPath $midFile -Raw -ErrorAction SilentlyContinue).Trim()
        }
        $goldMidFile = Join-Path $env:TEMP ("claude-gold-mid-check-" + [guid]::NewGuid().ToString('N') + ".txt")
        scp -o BatchMode=yes -o ConnectTimeout=10 -q "${Alias}:/etc/cursor-auth/golden/machine-id.txt" $goldMidFile 2>$null
        $goldMid = ''
        if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $goldMidFile)) {
            $goldMid = (Get-Content -LiteralPath $goldMidFile -Raw -ErrorAction SilentlyContinue).Trim()
        }
        Remove-Item -LiteralPath $goldMidFile -Force -ErrorAction SilentlyContinue
        if ($goldMid -and ($fileMid -ne $goldMid)) {
            $reasons += 'machineid_file_mismatch'
        }
    } catch {
        $reasons += 'machineid_file_check_failed'
    }

    $personalMain = 0'''

# Test-CursorAuthNeedsRefresh may not have $Alias in scope - check function signature
idx = pt.find('function Test-CursorAuthNeedsRefresh')
print('Test-CursorAuthNeedsRefresh:\n', pt[idx:idx+500])

if 'machineid_file_mismatch' not in pt:
    if needle not in pt:
        raise SystemExit('needs refresh needle missing')
    # Check if function has Alias param
    sig = pt[idx:idx+300]
    if '[string]$Alias' not in sig and 'Alias' not in sig.split('{')[0]:
        # add optional Alias or skip scp in needs refresh - skip heal on sync path is enough
        print('WARN Test-CursorAuthNeedsRefresh has no Alias - skip adding scp check there')
    else:
        pt = pt.replace(needle, insert, 1)
        print('OK needs refresh machineid check')
else:
    print('SKIP needs refresh already has mismatch')

ps.write_text(pt, encoding='utf-8', newline='\n')

# Update test-cursor-auth-merge.ps1 to expect Write-CursorProfileMachineId and machineid heal
test = root / 'scripts/client/tests/test-cursor-auth-merge.ps1'
tt = test.read_text(encoding='utf-8')
if 'Write-CursorProfileMachineId' not in tt:
    tt = tt.replace(
        "Assert ($src -match 'AlreadyComplete') 'auth sync skips when local tokens complete'",
        "Assert ($src -match 'Write-CursorProfileMachineId') 'writes Electron machineid file'\n"
        "Assert ($src -match 'machineid healed') 'skip path still heals machineid'\n"
        "Assert ($src -match 'AlreadyComplete') 'auth sync skips when local tokens complete'"
    )
    test.write_text(tt, encoding='utf-8', newline='\n')
    print('OK test updated')
else:
    print('SKIP test')

# bump .30
for rel in [
    'scripts/client/mac/connect.sh',
    'scripts/client/windows/connect.ps1',
    'scripts/client/mac/connect-version.txt',
    'scripts/client/windows/connect-version.txt',
    'publish/README.txt',
    'publish/README-sepidz.txt',
    'CLAUDE.md',
]:
    p = root / rel
    c = p.read_text(encoding='utf-8')
    c2 = c.replace('20260717.29', '20260717.30').replace('20260717.28', '20260717.30')
    if c2 != c:
        if rel.endswith('.sh') or 'mac/connect' in rel:
            p.write_bytes(c2.replace('\r\n','\n').replace('\r','\n').encode())
        else:
            p.write_text(c2, encoding='utf-8')
        print('bumped', rel)

# ensure mac scripts LF
for rel in ['scripts/client/mac/connect.sh', 'scripts/client/git-mode.sh', 'scripts/client/connect-ui.sh']:
    p = root / rel
    p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b'\n'))

# Doc note in client-connect.md if login section exists
doc = root / 'docs/client-connect.md'
d = doc.read_text(encoding='utf-8')
if 'machineid' not in d.lower():
    # find Reload Window section
    marker = 'Developer → Reload Window'
    if marker in d or 'Reload Window' in d:
        d = d.replace(
            'After auth sync, if Chat messages fail: **Developer → Reload Window** in the `[Claude Server]` profile window.',
            'After auth sync, if Chat messages fail or Cursor asks to log in: **Developer → Reload Window** in the `[Claude Server]` profile window.\n'
            'Connect scripts keep the profile `machineid` file aligned with the server golden identity (required for login to stick).',
            2  # both win and mac if duplicated
        )
        doc.write_text(d, encoding='utf-8', newline='\n')
        print('OK docs')
    else:
        print('WARN docs marker')
else:
    print('SKIP docs')

print('done')
