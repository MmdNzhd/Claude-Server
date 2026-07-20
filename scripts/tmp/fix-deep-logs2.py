from pathlib import Path
import re

# Fix designer Die - single line form
p = Path('scripts/client/users/designer/connect.ps1')
c = p.read_text(encoding='utf-8')
old = 'function Die($m)  { Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1 }'
new = '''function Die($m)  {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog "FAIL DIE: $m" 'ERROR' }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}'''
if old in c:
    c = c.replace(old, new, 1)
    print('OK designer Die')
elif 'FAIL DIE:' in c:
    print('designer Die already OK')
else:
    print('designer Die pattern miss', repr(c[c.find('function Die'):c.find('function Die')+180]))

# StepFail in designer
if 'FAIL STEP' not in c:
    # find StepFail
    idx = c.find('function StepFail')
    print('StepFail snippet', repr(c[idx:idx+250]))
    old_sf = None
p.write_text(c, encoding='utf-8', newline='\n')

# Verify key strings in connect.ps1
win = Path('scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
for s in ['FAIL SSH_QUOTE', 'CONNECT_ATTEMPT', 'INTERACTIVE: project_menu_shown', 'FAIL MENU_ABORT', 'FAIL LAPTOP_SSH_BOOT', 'FAIL CONNECT_UNREACHABLE', 'FAIL SERVER_SCRIPT_PUSH', '20260720.7']:
    print(('OK' if s in win else 'MISS'), s)

ui = Path('scripts/client/connect-ui.sh').read_text(encoding='utf-8')
print('connect_log_ts', 'connect_log_ts()' in ui)
print('uses connect_log_ts', '$(connect_log_ts)' in ui or 'connect_log_ts)' in ui)

upd = Path('scripts/client/mac/connect-update.sh').read_text(encoding='utf-8')
print('FAIL UPDATE_PREFIX inject', 'FAIL UPDATE_:' in upd or 'FAIL UPDATE_' in upd)
# show inject area
idx = upd.find('_update_file_log()')
print(upd[idx:idx+350])

# Harden hard regression suite
tp = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
tc = tp.read_text(encoding='utf-8')
if 'FAIL SSH_QUOTE' not in tc:
    insert = """
Write-Host '--- H) Deep log completeness (20260720.7) ---' -ForegroundColor Cyan
Assert ($win -match 'FAIL SSH_QUOTE') 'SSH quoting glitch logs FAIL SSH_QUOTE'
Assert ($win -match 'CONNECT_ATTEMPT') 'connect retry attempts logged'
Assert ($win -match 'FAIL CONNECT_UNREACHABLE') 'unreachable after 10 attempts logs FAIL CONNECT_UNREACHABLE'
Assert ($win -match 'INTERACTIVE: project_menu_shown') 'project menu wait is logged'
Assert ($win -match 'FAIL MENU_ABORT') 'empty Choose-Project logs FAIL MENU_ABORT'
Assert ($win -match 'FAIL LAPTOP_SSH_BOOT') 'Ensure-LaptopSshReady false logs FAIL LAPTOP_SSH_BOOT'
Assert ($win -match 'FAIL SERVER_SCRIPT_PUSH') 'server script push fail logged'
\$uiSh = Get-Content (Join-Path \$Client 'connect-ui.sh') -Raw
Assert (\$uiSh -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'

"""
    # Fix - the $ escapes wrong for writing into ps1 file
    insert = """
Write-Host '--- H) Deep log completeness (20260720.7) ---' -ForegroundColor Cyan
Assert ($win -match 'FAIL SSH_QUOTE') 'SSH quoting glitch logs FAIL SSH_QUOTE'
Assert ($win -match 'CONNECT_ATTEMPT') 'connect retry attempts logged'
Assert ($win -match 'FAIL CONNECT_UNREACHABLE') 'unreachable after 10 attempts logs FAIL CONNECT_UNREACHABLE'
Assert ($win -match 'INTERACTIVE: project_menu_shown') 'project menu wait is logged'
Assert ($win -match 'FAIL MENU_ABORT') 'empty Choose-Project logs FAIL MENU_ABORT'
Assert ($win -match 'FAIL LAPTOP_SSH_BOOT') 'Ensure-LaptopSshReady false logs FAIL LAPTOP_SSH_BOOT'
Assert ($win -match 'FAIL SERVER_SCRIPT_PUSH') 'server script push fail logged'
$uiSh2 = Get-Content (Join-Path $Client 'connect-ui.sh') -Raw
Assert ($uiSh2 -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'

"""
    marker = "Write-Host ''\nWrite-Host (\"Hard regressions:"
    if marker not in tc:
        raise SystemExit('marker missing')
    tc = tc.replace(marker, insert + marker, 1)
    # hard suite uses $ui not $win for connect-ui - check variable name for connect.ps1
    if '$win =' not in tc and '$win -match' in insert:
        # hard suite loads connect.ps1 as? check
        print('suite vars:', [l for l in tc.splitlines() if 'Get-Content' in l and 'connect' in l][:8])
    tp.write_text(tc, encoding='utf-8', newline='\n')
    print('OK hard H')
print('DONE')
