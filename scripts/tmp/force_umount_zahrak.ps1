$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
$py = @'
import os, subprocess
# show mounts
print("PROC", flush=True)
for ln in open("/proc/mounts"):
    if "/home/zahrak/mounts" in ln:
        print(ln.strip(), flush=True)

for mid in ("frontend", "backend"):
    mp = f"/home/zahrak/mounts/{mid}"
    print(f"--- {mp}", flush=True)
    # try as root
    for cmd in (
        f"fusermount -uz {mp}",
        f"umount -l {mp}",
        f"umount -f {mp}",
    ):
        r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
        print(cmd, "ec", r.returncode, (r.stderr or r.stdout or "").strip()[:120], flush=True)
    # as user
    r = subprocess.run(["sudo","-u","zahrak","-H","bash","-lc", f"fusermount -uz {mp} || umount -l {mp} || true"], text=True, capture_output=True)
    print("as_user", (r.stderr or r.stdout or "").strip()[:120], flush=True)

print("AFTER", flush=True)
left=[]
for ln in open("/proc/mounts"):
    if "/home/zahrak/mounts" in ln:
        print(ln.strip(), flush=True)
        left.append(ln)
print("left", len(left), flush=True)
'@
[IO.File]::WriteAllText("$env:TEMP\fuz.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\fuz.py" 'sepidz@192.168.250.70:/tmp/fuz.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/fuz.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\fuz.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\fuz.sh" 'sepidz@192.168.250.70:/tmp/fuz.sh'
ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 'bash /tmp/fuz.sh'
