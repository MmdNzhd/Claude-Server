from pathlib import Path
broken = "${rpath//" + "'" + "/" + "''" + "}"
escaped = "${rpath//" + "\\'" + "/" + "\\'\\'" + "}"
for label, p in [
    ('repo', Path('scripts/server/claude-mount.sh')),
]:
    t = p.read_text(encoding='utf-8')
    print(label, 'broken', t.count(broken), 'escaped', t.count(escaped))
    for i, l in enumerate(t.splitlines(), 1):
        if 'safe=' in l and 'rpath' in l:
            print(i, repr(l))
