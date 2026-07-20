from pathlib import Path
import re
lines = Path('scripts/server/claude-mount.sh').read_text(encoding='utf-8').splitlines()
for i, l in enumerate(lines, 1):
    if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{', l) and 80 <= i <= 280:
        print(f'DEF {i}: {l}')

depth = 0
in_sq = in_dq = False
for i, l in enumerate(lines, 1):
    j = 0
    while j < len(l):
        c = l[j]
        if in_sq:
            if c == "'":
                in_sq = False
            j += 1
            continue
        if in_dq:
            if c == '\\' and j + 1 < len(l):
                j += 2
                continue
            if c == '"':
                in_dq = False
            j += 1
            continue
        if c == '#' and not in_sq and not in_dq:
            break
        if c == "'":
            in_sq = True
            j += 1
            continue
        if c == '"':
            in_dq = True
            j += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        j += 1
    if i in range(130, 250) and (
        i in (130, 140, 150, 160, 166, 169, 184, 191, 224, 226, 243, 244)
        or re.match(r'^[a-zA-Z_].*\(\)\s*\{', l)
        or l.strip() == '}'
    ):
        print(f'{i:4} depth={depth} {l[:100]}')
print('final_depth', depth)
# Also check OLD broken hash file
old = Path(r'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\server\claude-mount.sh')
if old.exists():
    ol = old.read_text(encoding='utf-8', errors='replace').splitlines()
    print('OLD defs:')
    for i, l in enumerate(ol, 1):
        if '_emit_git_hide_warn' in l:
            print(f'  {i}: {l[:80]}')
