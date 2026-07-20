from pathlib import Path
root=Path(r'D:\Smart\Claude-Code-Server')
out=[]
# exact line numbers for key fixes
files={
 'scripts/client/git-mode.ps1': ['function Push-ServerConnectConf','ClearActiveMount','Preserve existing server ACTIVE_MOUNT','Push-ServerConnectConf -ClearActiveMount'],
 'scripts/client/windows/connect.ps1': ['Push-ServerConnectConf -ClearActiveMount'],
 'scripts/client/git-mode.sh': ['push_server_connect_conf()','Preserve server ACTIVE_MOUNT','push_server_connect_conf --clear'],
 'scripts/server/claude-automount.sh': ['VSCODE_RESOLVING_ENVIRONMENT','_ppargs','claude-last-active-mount','timeout 4','timeout 8'],
 'scripts/server/claude-self-heal.sh': ['_heal_active_remount','_heal_connect_log_bufs','_heal_zombie_readable','_infer_active_mount'],
 'scripts/server/claude-watchdog.sh': ['need_remount','HEAL_EVERY','Never use mountpoint'],
}
for rel, keys in files.items():
    p=root/rel
    if not p.exists():
        out.append(f'MISSING {rel}')
        continue
    lines=p.read_text(encoding='utf-8',errors='replace').splitlines()
    out.append(f'## {rel} ({len(lines)} lines)')
    for key in keys:
        hits=[(i+1,L.strip()) for i,L in enumerate(lines) if key in L]
        if not hits:
            out.append(f'  NOT_FOUND: {key}')
        for i,L in hits[:3]:
            out.append(f'  L{i}: {L[:140]}')
Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\precise_code.out').write_text('\n'.join(out),encoding='utf-8')
print('ok')
