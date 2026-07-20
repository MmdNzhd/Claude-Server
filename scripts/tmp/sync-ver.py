from pathlib import Path
import re
ver = '20260720.2'
root = Path('.')
pairs = [
    (root / 'scripts/client/windows/connect.ps1', r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'"),
    (root / 'scripts/client/mac/connect.sh', r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'"),
]
for p, pat, rep in pairs:
    c = p.read_text(encoding='utf-8')
    c2, n = re.subn(pat, rep, c, count=1)
    if n != 1:
        raise SystemExit(f'{p}: replace count {n}')
    p.write_text(c2, encoding='utf-8', newline='\n')
    print('OK', p)
for p in [root / 'scripts/client/windows/connect-version.txt', root / 'scripts/client/mac/connect-version.txt']:
    p.write_text(ver + '\n', encoding='utf-8')
    print('OK', p)
print('DONE', ver)
