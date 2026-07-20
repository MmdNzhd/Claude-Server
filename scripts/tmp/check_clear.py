from pathlib import Path
out=[]
ps=Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1').read_text(encoding='utf-8')
i=ps.find('function Push-ServerConnectConf')
out.append(ps[i:i+1400])
out.append('\n==== CLEAR around Push ClearActive ====')
for line in ps.splitlines():
    if 'ClearActiveMount' in line or ('Push-ServerConnectConf' in line and 'Clear' in line):
        out.append(line)
sh=Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh').read_text(encoding='utf-8')
out.append('\n==== sh push ====')
k=sh.find('push_server_connect_conf()')
out.append(sh[k:k+1000])
out.append('\n==== sh clear call ====')
idx=0
while True:
    k=sh.find('push_server_connect_conf --clear', idx)
    if k<0: break
    out.append(sh[max(0,k-120):k+40])
    idx=k+1
Path(r'D:\Smart\Claude-Code-Server\scripts\tmp\check_clear.out').write_text('\n'.join(out), encoding='utf-8')
print('ok')
