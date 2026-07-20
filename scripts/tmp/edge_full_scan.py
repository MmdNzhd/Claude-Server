# -*- coding: utf-8 -*-
import sys, re
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
root = Path(r'D:\Smart\Claude-Code-Server')
files = {
  'ui': root/'scripts/client/connect-ui.ps1',
  'cp': root/'scripts/client/windows/connect.ps1',
  'bat': root/'scripts/client/windows/connect.bat',
  'upd': root/'scripts/client/windows/connect-update.ps1',
  'gm': root/'scripts/client/git-mode.ps1',
  'el': root/'scripts/client/editor-launch.ps1',
  'sh': root/'scripts/client/connect-ui.sh',
  'csh': root/'scripts/client/mac/connect.sh',
  'ush': root/'scripts/client/mac/connect-update.sh',
  'pub': root/'publish/publish.ps1',
}
T = {k: p.read_text(encoding='utf-8', errors='replace') for k,p in files.items() if p.exists()}
print('files', {k: len(v) for k,v in T.items()})

# patterns of interest in connect.ps1
for label, pat in [
  ('EnsureTunnel', r'function Ensure-Tunnel|Ensure-Tunnel|ENSURE_TUNNEL'),
  ('Orphan', r'ORPHAN|orphan'),
  ('Stale', r'STALE_FORWARD|port still busy'),
  ('ActiveMount', r'ACTIVE_MOUNT|ClearActiveMount|-ClearActiveMount'),
  ('Editor', r'Opening Cursor|LAUNCH|editor_opened'),
  ('Recover', r'recover|Connection dropped|TUNNEL_DROP'),
  ('InitLog', r'Initialize-ConnectLog'),
  ('CloseLog', r'Close-ConnectLog'),
  ('Update', r'connect-update|Updated to'),
  ('Mutex', r'mutex|NamedMutex|single.?instance|AlreadyRunning'),
  ('Elevated', r'Test-IsElevated|elevated|RunAs'),
  ('Alias', r'claude-server-sepidz|Alias\s*='),
]:
    hits = []
    for k,t in T.items():
        n = len(re.findall(pat, t, re.I))
        if n: hits.append(f'{k}:{n}')
    print(f'{label}: {hits or ["NONE"]}')

# connect.ps1 size / log call density
cp=T['cp']
print('connect.ps1 lines', cp.count('\n')+1)
print('Write-ConnectLog calls', len(re.findall(r'Write-ConnectLog', cp)))
print('Sync calls', len(re.findall(r'Sync-ConnectLogToServer', cp+T['ui'])))

# bat flow
bat=T['bat']
print('--- bat key lines ---')
for i,l in enumerate(bat.splitlines(),1):
    if re.search(r'update|powershell|BOOTSTRAP|connect\.ps1|elevat|RunAs', l, re.I):
        print(f'{i}: {l[:120]}')
