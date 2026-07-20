from pathlib import Path
gm=Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1').read_text(encoding='utf-8')
# find bg_alive context
i=gm.find('TUNNEL_SYNC: bg_alive')
print(gm[i-400:i+200])
print('====')
# Clear-ServerStale full function already have
# Find wait counts 8 and 500
import re
for m in re.finditer(r'Start-Sleep[^\n]+|for \(\$i = 1; \$i -le \d+', gm):
    if 'STALE' in gm[max(0,m.start()-200):m.start()+50] or 'Sleep' in m.group():
        pass
print('stale sleeps:', re.findall(r'for \(\$i = 1; \$i -le (\d+)\).*?Start-Sleep -Milliseconds (\d+)', gm, re.S)[:5])
# also in sh
sh=Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh').read_text(encoding='utf-8')
print('sh stale:', re.findall(r'for i in \$\(seq 1 (\d+)\).*?sleep[^\n]+', sh, re.S)[:3])
print([l for l in sh.splitlines() if 'seq 1' in l or 'sleep 0' in l][:15])
