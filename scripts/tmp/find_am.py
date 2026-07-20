from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
lines = p.read_text(encoding='utf-8', errors='replace').splitlines()
for i, L in enumerate(lines, 1):
    if any(k in L for k in ('ACTIVE_MOUNT=%s', 'Write-RemoteConnectConf', 'CLEAR_MOUNT', 'function Set-Remote', 'function Write-Remote', '$am')):
        if 'ACTIVE_MOUNT' in L or 'CLEAR_MOUNT' in L or 'Write-Remote' in L or 'Set-Remote' in L or 'function' in L and 'Conf' in L:
            print(f'{i}: {L[:160]}')
print('--- context 850-875 ---')
for i in range(849, min(875, len(lines))):
    print(f'{i+1}: {lines[i][:160]}')
