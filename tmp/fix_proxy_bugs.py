from pathlib import Path

# Fix Windows git-mode.ps1 redirect
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
# When run via laptop-exec on Windows, cwd is repo root — use relative
import os
os.chdir(r'D:\Smart\Claude-Code-Server')
p = Path('scripts/client/git-mode.ps1')
t = p.read_text(encoding='utf-8')
old = "& ssh @($sshBase + @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=2', $Alias, $remoteCmd) 2>$null)"
new = "& ssh @($sshBase + @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=2', $Alias, $remoteCmd)) 2>$null"
if old not in t:
    raise SystemExit('PS old pattern not found: ' + repr(t[t.find('remoteCmd'):t.find('remoteCmd')+200]))
t = t.replace(old, new, 1)
p.write_text(t, encoding='utf-8')
print('PS_REDIRECT_FIXED')

# Fix Mac SO_REUSEADDR typo
p2 = Path('scripts/client/git-mode.sh')
t2 = p2.read_text(encoding='utf-8')
old2 = 'socket.SOL_REUSEADDR'
new2 = 'socket.SO_REUSEADDR'
c = t2.count(old2)
if c == 0:
    print('MAC_SO_ALREADY_OK_OR_MISSING')
else:
    t2 = t2.replace(old2, new2)
    p2.write_text(t2, encoding='utf-8')
    print(f'MAC_SO_FIXED count={c}')
