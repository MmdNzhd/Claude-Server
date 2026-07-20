from pathlib import Path
ps = Path(r'D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1')
pt = ps.read_text(encoding='utf-8')
old = '''        $midHeal = $null
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
new = '''        $midHeal = $null
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
    raise SystemExit('block missing')
ps.write_text(pt.replace(old, new, 1), encoding='utf-8', newline='\n')
print('OK removed GetValue')
assert 'GetValue' not in ps.read_text(encoding='utf-8')
print('no GetValue left')
