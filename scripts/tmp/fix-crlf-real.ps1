$ErrorActionPreference='Continue'
$py = @'
import os
def check(label, path):
  rp=os.path.realpath(path)
  if not os.path.isfile(rp):
    print(label, "MISSING", path); return
  raw=open(rp,"rb").read()
  cr=raw.count(b"\r")
  print(label, "CR_COUNT", cr, "bytes", len(raw), rp)
  if cr:
    open(rp,"wb").write(raw.replace(b"\r\n",b"\n").replace(b"\r",b"\n"))
    print(label, "STRIPPED")
for home in sorted(os.listdir("/home")):
  p=f"/home/{home}/.local/bin/laptop-exec"
  if os.path.exists(p):
    check(home, p)
check("SYSTEM", "/usr/local/bin/laptop-exec")
check("MOUNT", "/usr/local/lib/claude-mount")
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
Write-Host '==== SEPIDZ ===='
& ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 "echo $b64 | base64 -d > /tmp/crlf_real.py"
# need sudo for system + some homes
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl=[char]10
$wrap='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/crlf_real.py'+$nl
[IO.File]::WriteAllText("$env:TEMP\crlf_real_wrap.sh",$wrap)
& scp -o BatchMode=yes -q "$env:TEMP\crlf_real_wrap.sh" sepidz@192.168.250.70:/tmp/crlf_real_wrap.sh
& ssh -o BatchMode=yes -o ConnectTimeout=60 sepidz@192.168.250.70 'bash /tmp/crlf_real_wrap.sh'
Write-Host '==== SMART ===='
& ssh -o BatchMode=yes -o ConnectTimeout=20 smart@192.168.210.240 "echo $b64 | base64 -d > /tmp/crlf_real.py && sudo -n python3 /tmp/crlf_real.py"
# verify farzad settings via sudo
Write-Host '==== FARZAD SETTINGS ===='
$py2=@'
import json
for p in ["/home/farzadb/mounts/frontend/.vscode/settings.json","/home/farzadb/mounts/backend/.vscode/settings.json"]:
  d=json.load(open(p))
  print(p.split("/mounts/")[1], "git.enabled=", d.get("git.enabled"), "auto=", d.get("git.autoRepositoryDetection"))
'@
$b642=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py2))
$wrap2='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 -c "exec(__import__(\"base64\").b64decode(\"'+$b642+'\").decode())"'+$nl
# simpler scp
[IO.File]::WriteAllText("$env:TEMP\farzad_set_check.py",$py2)
& scp -o BatchMode=yes -q "$env:TEMP\farzad_set_check.py" sepidz@192.168.250.70:/tmp/farzad_set_check.py
$wrap3='#!/bin/bash'+$nl+'PW=$(echo '+$pwB64+' | base64 -d)'+$nl+'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_set_check.py'+$nl
[IO.File]::WriteAllText("$env:TEMP\farzad_set_wrap.sh",$wrap3)
& scp -o BatchMode=yes -q "$env:TEMP\farzad_set_wrap.sh" sepidz@192.168.250.70:/tmp/farzad_set_wrap.sh
& ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/farzad_set_wrap.sh'
