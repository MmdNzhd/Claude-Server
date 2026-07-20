from pathlib import Path

p = Path('scripts/server/claude-mount.sh')
t = p.read_text(encoding='utf-8')
broken = '${rpath//\'/\'\'}'  # this is WRONG representation

# Actual broken text in file uses raw quotes inside ${}: ${rpath//'/''}
broken_real = "${rpath//'/''}"
fixed_real = "${rpath//\\'/\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'}"  # no

# Correct bash form used elsewhere in this file:
fixed_real = r"${rpath//\'/\'\'}"

# But in the source FILE we need the characters: $ { r p a t h / / \ ' / \ ' \ ' }
# Looking at working lines via repr:
# local safe="${rpath//\'/\'\'}"

count = t.count("${rpath//'/''}")
print('broken_count', count)
if count < 1:
    # show candidates
    for i, line in enumerate(t.splitlines(), 1):
        if 'safe=' in line and 'rpath' in line:
            print(i, repr(line))
    raise SystemExit('no broken pattern')

t2 = t.replace("${rpath//'/''}", "${rpath//\\'/\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'\\'}")
# Stop - use chr construction
old = '${rpath//' + "'" + '/' + "''" + '}'
new = '${rpath//' + "\\'" + '/' + "\\'\\'" + '}'
print('old', repr(old))
print('new', repr(new))
print('old in file', old in t)
t2 = t.replace(old, new)
print('new count of old', t2.count(old))
print('new count of new', t2.count(new))
p.write_text(t2, encoding='utf-8', newline='\n')
print('wrote', p)
