from pathlib import Path
for rel in ['scripts/client/git-mode.ps1','scripts/client/windows/connect.ps1','scripts/client/git-mode.sh']:
    p=Path(r'D:\Smart\Claude-Code-Server')/rel
    if not p.exists(): continue
    lines=p.read_text(encoding='utf-8',errors='replace').splitlines()
    print('====', rel, '====')
    for i,L in enumerate(lines,1):
        if 'Push-ServerConnectConf' in L or 'push_server_connect' in L or 'ACTIVE_MOUNT=%s' in L:
            print(f'{i}: {L[:200]}')
            for j in range(max(0,i-4), min(len(lines), i+3)):
                if j+1!=i: print(f'   {j+1}| {lines[j][:180]}')
