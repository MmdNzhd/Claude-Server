from pathlib import Path
import re

p = Path('scripts/client/windows/connect.ps1')
c = p.read_text(encoding='utf-8')

# Verify first replace
if 'cannot_read_ak' not in c:
    raise SystemExit('frag replace missing')

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

# Also fix FAIL NEED_ADMIN message path - only when actually missing after readable check
# Invoke-LaptopAdminOps still OK for real missing keys / firewall

# bump version
ver = '20260720.6'
c2, n = re.subn(r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'", c, count=1)
if n != 1:
    raise SystemExit('ver bump fail')
p.write_text(c2, encoding='utf-8', newline='\n')

mac = Path('scripts/client/mac/connect.sh')
t = mac.read_text(encoding='utf-8')
t2, n = re.subn(r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'", t, count=1)
mac.write_text(t2, encoding='utf-8', newline='\n')
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text(ver + '\n', encoding='utf-8')

# hard regression
tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
if 'admin_ak unreadable unelevated' not in tc:
    tc = tc.replace(
        "Assert ($upd -match 'FAIL UPDATE_SWAP_IN_USE') 'connect-update.ps1 logs FAIL UPDATE_SWAP_IN_USE'\n",
        "Assert ($upd -match 'FAIL UPDATE_SWAP_IN_USE') 'connect-update.ps1 logs FAIL UPDATE_SWAP_IN_USE'\n\n"
        "Write-Host '--- G) Admin AK ACL false-positive ---' -ForegroundColor Cyan\n"
        "Assert ($win -match 'admin_ak unreadable unelevated') 'connect.ps1 skips NEED_ADMIN when admin_ak unreadable'\n"
        "Assert ($win -match 'cannot_read_ak') 'Test-AuthorizedKeyFragment returns null on access denied'\n"
        "Assert ($win -match '\\$null -eq \\$akHit') 'explicit null check for AK membership'\n",
        1,
    )
    # fix escaping for the assert - in the ps1 file we need $win and $null -eq $akHit as literal in single-quoted assert message side
    # The Assert line uses double quotes for the pattern in -match - careful
    tp.write_text(tc, encoding='utf-8', newline='\n')

print('OK', ver)
