from pathlib import Path
for rel in ['scripts/client/git-mode.ps1','scripts/client/windows/connect.ps1','scripts/client/git-mode.sh']:
    t=Path(r'D:\Smart\Claude-Code-Server',rel).read_text(encoding='utf-8')
    print(rel)
    print('  ClearActiveMount', t.count('ClearActiveMount'))
    print('  preserve', 'Preserve existing server ACTIVE_MOUNT' in t or 'Preserve server ACTIVE_MOUNT' in t)
    print('  ActiveMount \'\' left', t.count("ActiveMount ''"))
    print('  --clear', t.count('--clear'))
