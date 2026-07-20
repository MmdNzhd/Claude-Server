from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
ps = root / 'scripts/client/cursor-auth-laptop.ps1'
pt = ps.read_text(encoding='utf-8')

old = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
        Write-AuthSyncLog "skip already complete golden_exported_at=$goldenExportedAt" 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=true skipped=true already_complete=true db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_already_complete'
        return [PSCustomObject]@{
            Ok              = $true
            Skipped         = $true
            AlreadyComplete = $true
        }
    }'''

new = '''    if (-not $Force -and $goldenCurrent -and (Test-LocalCursorAuthComplete -DbPath $dbPath)) {
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
        if ($midHeal) { Write-CursorProfileMachineId -MachineId $midHeal | Out-Null }
        Write-AuthSyncLog "skip already complete golden_exported_at=$goldenExportedAt (machineid healed)" 'DEBUG'
        Write-AuthSyncLog "AUTH_SYNC: result force=$Force ok=true skipped=true already_complete=true db_bytes=$dbBytes wal_bytes=$walBytes" 'INFO'
        $authTotalSw.Stop()
        Write-AuthPerfLog -Mark 'auth_total' -Ms $authTotalSw.ElapsedMilliseconds -Extra 'path=skip_already_complete'
        return [PSCustomObject]@{
            Ok              = $true
            Skipped         = $true
            AlreadyComplete = $true
        }
    }'''

if old not in pt:
    raise SystemExit('windows skip not found')
pt = pt.replace(old, new, 1)

# Also add machineid mismatch to Test-CursorAuthNeedsRefresh
if 'machineid_file_mismatch' not in pt:
    # find serviceMachineId_empty block
    needle = "if (-not [CursorAuthSqlite]::HasNonEmptyValue($DbPath, 'storage.serviceMachineId')) {\n            $reasons += 'serviceMachineId_empty'\n        }"
    # looser search
    idx = pt.find("serviceMachineId_empty")
    if idx < 0:
        raise SystemExit('serviceMachineId_empty not found')
    # insert after that if block
    # Find the closing of that if and next lines
    chunk = pt[idx-200:idx+400]
    print('CHUNK:\n', chunk)

ps.write_text(pt, encoding='utf-8', newline='\n')
print('OK windows skip patched')
