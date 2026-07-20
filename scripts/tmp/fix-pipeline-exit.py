from pathlib import Path
import re
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
t = p.read_text(encoding='utf-8')
# Find session-log inclusion
for i,l in enumerate(t.splitlines(),1):
    if 'session-log' in l.lower() or 'SESSION_FILTER' in l:
        if i>0: print(f'{i}:{l}')
