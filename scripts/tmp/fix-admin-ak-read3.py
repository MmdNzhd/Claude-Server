from pathlib import Path
import re

p = Path('scripts/client/windows/connect.ps1')
c = p.read_text(encoding='utf-8')

old_frag = '''function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    $pattern = [regex]::Escape($PubFragment)
    return [bool](Select-String -Path $Path -Pattern $pattern -Quiet -ErrorAction SilentlyContinue)
}
'''

new_frag = '''function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    # Returns: $true / $false / $null (= unreadable; do NOT treat as missing).
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $Path -ErrorAction Stop
        $pattern = [regex]::Escape($PubFragment)
        return [bool]($raw | Where-Object { $_ -match $pattern })
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("LAPTOP_SSH: cannot_read_ak path=$Path err=$($_.Exception.Message)") 'WARN'
        }
        return $null
    }
}
'''

if old_frag not in c:
    raise SystemExit('frag not found')
c = c.replace(old_frag, new_frag, 1)

old = '''        if ($userIsAdmin -and (Test-Path $adminDir)) {
            if (-not (Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment)) {
                $reasons.Add('Server laptop key not in administrators_authorized_keys (Windows admin user)')
            }
        } elseif (-not (Test-AuthorizedKeyFragment -Path $userAk -PubFragment $PubFragment)) {
            $reasons.Add('Server laptop key not in authorized_keys')
        }
'''

new = '''        if ($userIsAdmin -and (Test-Path $adminDir)) {
            # Unelevated admin users cannot read administrators_authorized_keys (ACL=SYSTEM+Administrators).
            # Access-denied must NOT be treated as "key missing" or we infinite-prompt UAC.
            $akHit = Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment
            if ($null -eq $akHit) {
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog 'LAPTOP_SSH: admin_ak unreadable unelevated - skip membership check (key may already be installed)' 'WARN'
                }
            } elseif (-not $akHit) {
                $reasons.Add('Server laptop key not in administrators_authorized_keys (Windows admin user)')
            }
        } else {
            $akHit = Test-AuthorizedKeyFragment -Path $userAk -PubFragment $PubFragment
            if ($null -eq $akHit) {
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog 'LAPTOP_SSH: user authorized_keys unreadable' 'WARN'
                }
            } elseif (-not $akHit) {
                $reasons.Add('Server laptop key not in authorized_keys')
            }
        }
'''

if old not in c:
    raise SystemExit('ready block not found')
c = c.replace(old, new, 1)

ver = '20260720.6'
c, n = re.subn(r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'", c, count=1)
if n != 1:
    raise SystemExit('ver fail')
p.write_text(c, encoding='utf-8', newline='\n')

mac = Path('scripts/client/mac/connect.sh')
t = mac.read_text(encoding='utf-8')
t, n = re.subn(r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'", t, count=1)
mac.write_text(t, encoding='utf-8', newline='\n')
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text(ver + '\n', encoding='utf-8')

tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
if 'admin_ak unreadable unelevated' not in tc:
    insert = """
Write-Host '--- G) Admin AK ACL false-positive ---' -ForegroundColor Cyan
Assert ($win -match 'admin_ak unreadable unelevated') 'connect.ps1 skips NEED_ADMIN when admin_ak unreadable'
Assert ($win -match 'cannot_read_ak') 'Test-AuthorizedKeyFragment logs cannot_read_ak on access denied'
Assert ($win -match 'null -eq \\$akHit') 'explicit null check for AK membership'

"""
    marker = "Write-Host ''\nWrite-Host (\"Hard regressions:"
    if marker not in tc:
        raise SystemExit('marker missing')
    tc = tc.replace(marker, insert + marker, 1)
    tp.write_text(tc, encoding='utf-8', newline='\n')

print('OK', ver)
print('has cannot_read', 'cannot_read_ak' in p.read_text(encoding='utf-8'))
print('has unreadable', 'admin_ak unreadable unelevated' in p.read_text(encoding='utf-8'))
