from pathlib import Path
lines = Path('scripts/server/claude-mount.sh').read_text().splitlines()
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
        if c == '#':
            break
        if c == "'":
            in_sq = True
        elif c == '"':
            in_dq = True
        j += 1
    if in_sq or in_dq or i in (169, 226, 233, 243) or 'stub_ps' in l:
        print(f'{i:4} sq={int(in_sq)} dq={int(in_dq)} {l[:100]}')
print('END', 'sq', in_sq, 'dq', in_dq)
