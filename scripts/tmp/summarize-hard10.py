import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from pathlib import Path
tmp = Path('scripts/tmp')
for name in [f'TEST-HARD-{i}.md' for i in range(1, 10)] + ['SCOREBOARD-HARD10.md']:
    f = tmp / name
    if not f.exists():
        print(f'{name}: MISSING')
        continue
    text = f.read_text(encoding='utf-8', errors='replace')
    overall = '(no overall)'
    for ln in text.splitlines():
        u = ln.upper()
        if 'OVERALL' in u:
            overall = ln.strip()[:200]
            break
    print(f'{name}: {overall}')
