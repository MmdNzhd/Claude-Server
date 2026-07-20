from pathlib import Path
broken = "${rpath//" + "'" + "/" + "''" + "}"
escaped = "${rpath//" + "\\'" + "/" + "\\'\\'" + "}"
t = Path.home().joinpath('.local/bin/claude-mount').read_text()
print('remote', 'broken', t.count(broken), 'escaped', t.count(escaped))
for i, l in enumerate(t.splitlines(), 1):
    if 'safe=' in l and 'rpath' in l:
        print(i, repr(l))
# also search any leftover
idx = 0
while True:
    j = t.find(broken, idx)
    if j < 0:
        break
    print('FOUND_BROKEN_AT', j, repr(t[j:j+40]))
    idx = j + 1
