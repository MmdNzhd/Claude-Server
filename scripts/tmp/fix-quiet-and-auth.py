from pathlib import Path
# Quiet assignment
up = Path('scripts/client/windows/connect-update.ps1').read_text(encoding='utf-8')
print('script:Quiet assign', '$script:Quiet' in up)
print('Quiet param checks', up.count('$Quiet'))
# show Write-UpdateMsg
i = up.find('function Write-UpdateMsg')
print(up[i:i+250])
# ensure Quiet is assigned early
if '$script:Quiet' not in up or '$script:Quiet =' not in up:
    old = "Set-StrictMode -Version Latest\n$ErrorActionPreference = 'Continue'\n"
    new = old + "$script:Quiet = [bool]$Quiet\n"
    if old in up:
        up = up.replace(old, new, 1)
        # also fix Write-UpdateMsg to use script:Quiet if it uses $Quiet
        up2 = up.replace('if (-not $Quiet) {', 'if (-not $script:Quiet) {', 1)
        Path('scripts/client/windows/connect-update.ps1').write_text(up2, encoding='utf-8', newline='\n')
        print('FIXED Quiet')
    else:
        print('MISS quiet insert point')
else:
    print('Quiet already script-scoped')

# Auth test - what does it look for?
t = Path('scripts/client/tests/test-cursor-auth-merge.ps1').read_text(encoding='utf-8')
idx = t.find('Mac relaunches when AUTH_RELAUNCH')
print('test idx', idx)
print(t[idx-400:idx+600])
