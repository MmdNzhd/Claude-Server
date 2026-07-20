from pathlib import Path
sp = Path('scripts/client/tests/test-session-log-contracts.ps1')
sc = sp.read_text(encoding='utf-8')
# Fix bad variable names in inserted block
bad = """
Assert ($ui -match 'FAIL EXIT reason=') 'Wait-ConnectExit logs FAIL EXIT on non-zero code'
Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'
Assert ($winConnect -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ($winConnect -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ($winConnect -match 'FAIL ADMIN_UAC') 'connect.ps1 logs FAIL ADMIN_UAC'
$upd = Get-Content (Join-Path $root 'windows\\connect-update.ps1') -Raw -ErrorAction SilentlyContinue
if (-not $upd) { $upd = Get-Content (Join-Path $root 'connect-update.ps1') -Raw -ErrorAction SilentlyContinue }
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'
"""
good = """
Assert ($ui -match 'FAIL EXIT reason=') 'Wait-ConnectExit logs FAIL EXIT on non-zero code'
Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'
Assert ($ui -match 'MULTI_INSTANCE: allowed') 'multi-instance allowed (no global mutex)'
Assert ($win -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ($win -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ($win -match 'FAIL ADMIN_UAC') 'connect.ps1 logs FAIL ADMIN_UAC'
$upd = Get-Content (Join-Path $client 'windows\\connect-update.ps1') -Raw
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'
Assert ($bat -match 'FAIL UPDATE_BAT_EXIT') 'connect.bat logs FAIL UPDATE_BAT_EXIT'
"""
if bad.strip() in sc:
    sc = sc.replace(bad, good, 1)
elif 'FAIL EXIT reason=' in sc and '$winConnect' in sc:
    sc = sc.replace('$winConnect', '$win').replace("Join-Path $root", 'Join-Path $client')
    if 'MULTI_INSTANCE: allowed' not in sc:
        sc = sc.replace(
            "Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'",
            "Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'\nAssert ($ui -match 'MULTI_INSTANCE: allowed') 'multi-instance allowed (no global mutex)'",
            1,
        )
    if 'FAIL UPDATE_BAT_EXIT' not in sc:
        sc = sc.replace(
            "Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'",
            "Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'\nAssert ($bat -match 'FAIL UPDATE_BAT_EXIT') 'connect.bat logs FAIL UPDATE_BAT_EXIT'",
            1,
        )
    print('patched variants')
else:
    # already good or different
    print('checking current inserts...')
    print([l for l in sc.splitlines() if 'FAIL' in l or 'MULTI' in l or 'upd' in l])

if bad.strip() in sc or '$winConnect' in sc:
    pass
if good.strip() not in sc and 'FAIL NEED_ADMIN' in sc:
    # verify
    pass
if bad.strip() in Path('scripts/client/tests/test-session-log-contracts.ps1').read_text(encoding='utf-8'):
    sc = Path('scripts/client/tests/test-session-log-contracts.ps1').read_text(encoding='utf-8').replace(bad, good, 1)

sp.write_text(sc if 'FAIL NEED_ADMIN' in sc else Path('scripts/client/tests/test-session-log-contracts.ps1').read_text(encoding='utf-8'), encoding='utf-8', newline='\n')

# Re-read and force-good if needed
sc = sp.read_text(encoding='utf-8')
if '$winConnect' in sc or 'Join-Path $root' in sc:
    sc = sc.replace('$winConnect', '$win').replace('Join-Path $root', 'Join-Path $client')
if 'MULTI_INSTANCE: allowed' not in sc:
    sc = sc.replace(
        "Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'\n",
        "Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'\nAssert ($ui -match 'MULTI_INSTANCE: allowed') 'multi-instance allowed (no global mutex)'\n",
        1,
    )
if "Get-Content (Join-Path $client 'windows\\connect-update.ps1')" not in sc and 'FAIL UPDATE_UNHANDLED' in sc:
    pass
if 'FAIL UPDATE_BAT_EXIT' not in sc:
    sc = sc.replace(
        "Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'\n",
        "Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'\nAssert ($bat -match 'FAIL UPDATE_BAT_EXIT') 'connect.bat logs FAIL UPDATE_BAT_EXIT'\n",
        1,
    )
# Fix $upd line if still has -ErrorAction dual
if "if (-not $upd)" in sc:
    sc = sc.replace(
        "$upd = Get-Content (Join-Path $client 'windows\\connect-update.ps1') -Raw -ErrorAction SilentlyContinue\nif (-not $upd) { $upd = Get-Content (Join-Path $client 'connect-update.ps1') -Raw -ErrorAction SilentlyContinue }\n",
        "$upd = Get-Content (Join-Path $client 'windows\\connect-update.ps1') -Raw\n",
        1,
    )
sp.write_text(sc, encoding='utf-8', newline='\n')
print('--- final fail lines ---')
for l in sp.read_text(encoding='utf-8').splitlines():
    if 'FAIL' in l or 'MULTI' in l or '$upd' in l:
        print(l)
print('DONE')
