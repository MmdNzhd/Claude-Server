$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
foreach ($f in @('claude-self-heal.sh','claude-automount.sh','laptop-exec-setup.sh')) {
  scp -o BatchMode=yes -q "$root\scripts\server\$f" "sepidz@192.168.250.70:/tmp/$f"
}
$py = @'
import os, pwd
def lf(src, dst, mode=0o755):
    data=open(src,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
    open(dst,"wb").write(data); os.chmod(dst, mode); print("ok", dst)
lf("/tmp/claude-self-heal.sh","/usr/local/bin/claude-self-heal")
lf("/tmp/claude-self-heal.sh","/usr/local/lib/claude-server/claude-self-heal.sh")
lf("/tmp/claude-automount.sh","/usr/local/bin/claude-automount")
lf("/tmp/claude-automount.sh","/usr/local/lib/claude-automount")
lf("/tmp/laptop-exec-setup.sh","/usr/local/bin/laptop-exec-setup")
assert b"_heal_bin_crlf_all" in open("/usr/local/bin/claude-self-heal","rb").read()
assert b"claude-self-heal" in open("/usr/local/bin/claude-automount","rb").read()
for ent in pwd.getpwall():
    if ent.pw_uid < 1000: continue
    home=ent.pw_dir
    if not os.path.isdir(home): continue
    os.makedirs(f"{home}/.local/bin", exist_ok=True)
    for name in ("claude-self-heal","claude-automount"):
        src=f"/usr/local/bin/{name}"
        dst=f"{home}/.local/bin/{name}"
        data=open(src,"rb").read()
        open(dst,"wb").write(data); os.chmod(dst,0o755)
        try: os.chown(dst, ent.pw_uid, ent.pw_gid)
        except OSError: pass
print("WINMAC_DEPLOY_OK")
'@
[IO.File]::WriteAllText("$env:TEMP\rwm.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\rwm.py" 'sepidz@192.168.250.70:/tmp/rwm.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/rwm.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\rwm.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\rwm.sh" 'sepidz@192.168.250.70:/tmp/rwm.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/rwm.sh'
