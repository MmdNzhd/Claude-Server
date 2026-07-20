$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\server\claude-self-heal.sh' 'sepidz@192.168.250.70:/tmp/claude-self-heal.sh'
$py = @'
data=open("/tmp/claude-self-heal.sh","rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
open("/usr/local/bin/claude-self-heal","wb").write(data)
open("/usr/local/lib/claude-server/claude-self-heal.sh","wb").write(data)
import os
os.chmod("/usr/local/bin/claude-self-heal", 0o755)
assert b"Never use mountpoint" in data
print("HEAL_BIN_OK")
# verify no zahrak mounts
left=[ln for ln in open("/proc/mounts") if "/home/zahrak/mounts" in ln]
print("zahrak_left", len(left))
# ensure farzadb still healthy
import json
j=json.load(open("/home/farzadb/.cursor-server/data/User/settings.json"))
assert j.get("git.enabled") is False
print("farzadb_git_off_OK")
# conf GIT_MODE for alit
print("alit_conf", open("/home/alit/.claude-connect.conf").read().strip().replace("\n"," | "))
'@
[IO.File]::WriteAllText("$env:TEMP\rh.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\rh.py" 'sepidz@192.168.250.70:/tmp/rh.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/rh.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\rh.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\rh.sh" 'sepidz@192.168.250.70:/tmp/rh.sh'
ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 'bash /tmp/rh.sh'
