from pathlib import Path
import re

p = Path('scripts/client/windows/connect-update.ps1')
c = p.read_text(encoding='utf-8')
old = '''function Swap-LiveDir {
    param([string]$Live, [string]$NewDir, [string]$Bak)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $Bak -Parent)
    try {
        if (Test-Path -LiteralPath $Live) {
            if (Test-Path -LiteralPath $Bak) {
                Remove-Item -LiteralPath $Bak -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $Live -Destination $Bak -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $NewDir -Destination $Live -Force -ErrorAction Stop
        return $true
    } catch {
        Write-UpdateFileLog ("swap_fail live=$Live err=$($_.Exception.Message)") 'ERROR'
        Restore-FromBak -Live $Live -Bak $Bak
        return $false
    }
}
'''
new = '''function Swap-LiveDir {
    param([string]$Live, [string]$NewDir, [string]$Bak)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $Bak -Parent)
    try {
        if (Test-Path -LiteralPath $Live) {
            if (Test-Path -LiteralPath $Bak) {
                Remove-Item -LiteralPath $Bak -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $Live -Destination $Bak -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $NewDir -Destination $Live -Force -ErrorAction Stop
        return $true
    } catch {
        $err = $_.Exception.Message
        Write-UpdateFileLog ("swap_fail live=$Live err=$err") 'ERROR'
        # Self-update while connect.bat runs from Live: folder is "in use". Fall back to
        # in-place file overwrite (no Move-Item on Live), then caller exits 2 to relaunch.
        if ($err -match 'in use|being used by another process') {
            try {
                Restore-FromBak -Live $Live -Bak $Bak
                if (-not (Test-Path -LiteralPath $Live)) {
                    $null = New-Item -ItemType Directory -Force -Path $Live
                }
                Get-ChildItem -LiteralPath $NewDir -Recurse -Force -File -ErrorAction Stop | ForEach-Object {
                    $rel = $_.FullName.Substring($NewDir.Length).TrimStart('\\', '/')
                    $dest = Join-Path $Live $rel
                    $parent = Split-Path $dest -Parent
                    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                        $null = New-Item -ItemType Directory -Force -Path $parent
                    }
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                }
                Write-UpdateFileLog 'swap_inplace_ok reason=live_in_use' 'WARN'
                Write-UpdateFileLog 'FAIL UPDATE_SWAP_IN_USE: used inplace copy; relaunch required' 'ERROR'
                return $true
            } catch {
                Write-UpdateFileLog ("swap_inplace_fail err=$($_.Exception.Message)") 'ERROR'
            }
        }
        Restore-FromBak -Live $Live -Bak $Bak
        return $false
    }
}
'''
if old not in c:
    raise SystemExit('Swap-LiveDir not found')
c = c.replace(old, new, 1)
p.write_text(c, encoding='utf-8', newline='\n')

# bump version .5
ver = '20260720.5'
for rel, pat, rep in [
    ('scripts/client/windows/connect.ps1', r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'"),
    ('scripts/client/mac/connect.sh', r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'"),
]:
    pp = Path(rel)
    t = pp.read_text(encoding='utf-8')
    t2, n = re.subn(pat, rep, t, count=1)
    if n != 1:
        raise SystemExit(f'ver fail {rel}')
    pp.write_text(t2, encoding='utf-8', newline='\n')
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text(ver + '\n', encoding='utf-8')

# hard test assert
tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
if 'swap_inplace_ok' not in tc:
    tc = tc.replace(
        "Assert ($bat -match 'FAIL OUTDATED_SCRIPTS') 'connect.bat logs FAIL OUTDATED_SCRIPTS'\n",
        "Assert ($bat -match 'FAIL OUTDATED_SCRIPTS') 'connect.bat logs FAIL OUTDATED_SCRIPTS'\n"
        "Assert ($upd -match 'swap_inplace_ok') 'connect-update.ps1 inplace fallback when live in use'\n"
        "Assert ($upd -match 'FAIL UPDATE_SWAP_IN_USE') 'connect-update.ps1 logs FAIL UPDATE_SWAP_IN_USE'\n",
        1,
    )
    tp.write_text(tc, encoding='utf-8', newline='\n')
print('OK', ver)
