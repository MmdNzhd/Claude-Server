from pathlib import Path
p = Path('scripts/client/mac/connect.sh')
t = p.read_text(encoding='utf-8')
print('has Reloading string', 'Reloading $EDITOR_NAME (auth refresh)' in t)
print('CURSOR_AUTH_RELAUNCH count', t.count('CURSOR_AUTH_RELAUNCH'))
# find auth success / relaunch region
for needle in ['CURSOR_AUTH_RELAUNCH=1', 'auth refresh', 'AUTH_RELAUNCH', 'already on folder']:
    idx = 0
    while True:
        i = t.find(needle, idx)
        if i < 0: break
        line = t[:i].count('\n')+1
        print(f'--- {needle} @ {line} ---')
        print('\n'.join(t.splitlines()[line-3:line+12]))
        idx = i+1
        if needle != 'CURSOR_AUTH_RELAUNCH=1':
            break
