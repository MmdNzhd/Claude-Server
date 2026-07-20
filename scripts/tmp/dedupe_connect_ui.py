# -*- coding: utf-8 -*-
from pathlib import Path
import re

p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1')
t = p.read_text(encoding='utf-8')

first_sync = t.find('function Sync-ConnectLogToServer')
second_wm = t.find('function Write-ConnectLogSyncWatermark', first_sync + 10)
write_log = t.find('function Write-ConnectLog {', second_wm if second_wm >= 0 else 0)

print('first_sync', first_sync, 'second_wm', second_wm, 'write_log', write_log)
print('count Sync', t.count('function Sync-ConnectLogToServer'))
print('count Init', t.count('function Initialize-ConnectLog'))
print('count GetTarget', t.count('function Get-ConnectLogSyncTarget'))

if t.count('function Sync-ConnectLogToServer') > 1:
    if second_wm < 0 or write_log < 0:
        raise SystemExit('cannot find duplicate block')
    t = t[:second_wm] + t[write_log:]
    print('removed duplicate block bytes', write_log - second_wm)

old_cat = '        $cat = "cat `"$HOME/$remoteTmp`" >> `"$HOME/$remoteDay`" 2>/dev/null; rm -f `"$HOME/$remoteTmp`"; chmod 600 `"$HOME/$remoteDay`" 2>/dev/null; true"'
new_cat = "        $cat = 'cat \"$HOME/' + $remoteTmp + '\" >> \"$HOME/' + $remoteDay + '\" 2>/dev/null; rm -f \"$HOME/' + $remoteTmp + '\"; chmod 600 \"$HOME/' + $remoteDay + '\" 2>/dev/null; true'"
if old_cat in t:
    t = t.replace(old_cat, new_cat, 1)
    print('fixed $HOME expansion in $cat')
elif " + $remoteTmp + " in t and 'Sync-ConnectLogToServer' in t:
    print('$cat already fixed or different')
else:
    # show nearby cat lines
    for i, line in enumerate(t.splitlines()):
        if 'remoteTmp' in line and 'cat' in line.lower():
            print(i+1, line)

# Verify single Sync, no bool returns
sync_start = t.find('function Sync-ConnectLogToServer')
sync_end = t.find('function Write-ConnectLog {', sync_start)
sync_body = t[sync_start:sync_end]
assert t.count('function Sync-ConnectLogToServer') == 1, 'still multiple Sync'
assert t.count('function Initialize-ConnectLog') == 1, 'still multiple Init'
assert t.count('function Get-ConnectLogSyncTarget') == 1, 'still multiple GetTarget'
for bad in ('return $false', 'return $true', 'return $scpOk'):
    if bad in sync_body:
        raise SystemExit(f'Sync still has {bad}')
assert 'LastConnectLogSyncOk' in sync_body
assert 'TRACE/DEBUG stay local' in t
assert "+ $remoteTmp +" in sync_body or "'$HOME/" in sync_body

# full function names with hyphens
funcs = re.findall(r'^function ([A-Za-z0-9-]+)', t, re.M)
from collections import Counter
dups = {k:v for k,v in Counter(funcs).items() if v>1}
if dups:
    raise SystemExit(f'still real dups: {dups}')

p.write_text(t, encoding='utf-8', newline='\n')
print('WROTE OK lines', len(t.splitlines()), 'funcs', len(funcs))
