from pathlib import Path
p = Path('scripts/client/tests/test-p0-connect-fixes.ps1')
t = p.read_text(encoding='utf-8')
for i, line in enumerate(t.splitlines(), 1):
    if 'CONNECT_VERSION' in line and 'Assert' in line and 'mac' in line.lower():
        print(f'{i}:{line}')
# replace any .10 left in CONNECT_VERSION asserts
t2 = t.replace("CONNECT_VERSION='20260720\\.10'", "CONNECT_VERSION='20260720\\.21'")
t2 = t2.replace('20260720.10', '20260720.21')
p.write_text(t2, encoding='utf-8', newline='\n')
print('written', t2 != t)
for i, line in enumerate(t2.splitlines(), 1):
    if 'CONNECT_VERSION' in line and 'Assert' in line:
        print(f'NEW {i}:{line}')
