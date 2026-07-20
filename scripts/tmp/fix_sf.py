from pathlib import Path
p=Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz-matrix.ps1')
t=p.read_text(encoding='utf-8')
old="sf=$(grep -c \"Unable to resolve your shell environment\" \"$ra\" 2>/dev/null || echo 0)"
new="sf=$(grep -c \"Unable to resolve your shell environment\" \"$ra\" 2>/dev/null || true); sf=${sf:-0}"
if old in t:
    t=t.replace(old,new)
    p.write_text(t,encoding='utf-8')
    print('fixed sf')
else:
    print('pattern not found')
    for L in t.splitlines():
        if 'shell environment' in L: print(repr(L))
