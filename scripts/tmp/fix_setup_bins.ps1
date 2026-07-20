$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\server\laptop-exec-setup.sh' 'sepidz@192.168.250.70:/tmp/laptop-exec-setup.sh'
$py = @'
import os, pwd
src="/tmp/laptop-exec-setup.sh"
data=open(src,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
open("/usr/local/bin/laptop-exec-setup","wb").write(data)
os.chmod("/usr/local/bin/laptop-exec-setup",0o755)
n=0
for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home=ent.pw_dir
    if not os.path.isdir(home): continue
    if not (os.path.isdir(f"{home}/.cursor-server") or os.path.isfile(f"{home}/.claude-connect.conf")):
        continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    dst=f"{home}/.local/bin/laptop-exec-setup"
    open(dst,"wb").write(data)
    os.chmod(dst,0o755)
    try: os.chown(dst, ent.pw_uid, ent.pw_gid)
    except OSError: pass
    # also ensure heal+automount+le present
    for name in ("claude-self-heal","claude-automount","laptop-exec"):
        s=f"/usr/local/bin/{name}"
        if not os.path.isfile(s): continue
        d=f"{home}/.local/bin/{name}"
        open(d,"wb").write(open(s,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b""))
        os.chmod(d,0o755)
        try: os.chown(d, ent.pw_uid, ent.pw_gid)
        except OSError: pass
    n+=1
    print("ok", ent.pw_name)
print(f"SETUP_BINS n={n}")
'@
[IO.File]::WriteAllText("$env:TEMP\fsb.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\fsb.py" 'sepidz@192.168.250.70:/tmp/fsb.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/fsb.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\fsb.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\fsb.sh" 'sepidz@192.168.250.70:/tmp/fsb.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/fsb.sh'
