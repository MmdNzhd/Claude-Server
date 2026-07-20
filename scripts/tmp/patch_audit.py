from pathlib import Path
p=Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz-round-audit.ps1')
t=p.read_text(encoding='utf-8')
t=t.replace('S sudo -u ','printf \'%s\\n\' "$PW" | sudo -S -u ')
# fix the ones that became broken - the pattern was "S sudo -u \"$u\" -H ..." 
# after replace: printf '%s\n' "$PW" | sudo -S -u "$u" -H ...
# Good. But "S bash -c" should stay.
p.write_text(t, encoding='utf-8')
print('patched', t.count('printf \'%s\\n\' "$PW" | sudo -S -u '))
