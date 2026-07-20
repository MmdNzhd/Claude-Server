$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

Write-Host 'REPO windows=' ((Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim())
Write-Host 'REPO mac=' ((Get-Content "$root\scripts\client\mac\connect-version.txt" -Raw).Trim())
Write-Host 'REPO connect.ps1=' ((Select-String -Path "$root\scripts\client\windows\connect.ps1" -Pattern "ConnectVersion\s*=" | Select-Object -First 1).Line.Trim())
Write-Host 'REPO connect.sh=' ((Select-String -Path "$root\scripts\client\mac\connect.sh" -Pattern "CONNECT_VERSION=" | Select-Object -First 1).Line.Trim())

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
$py = @'
import os,re
base="/usr/local/share/claude-client"
print("bundle_txt=", open(base+"/connect-version.txt").read().strip())
for rel in ["connect.ps1","git-mode.ps1","mac/connect.sh","mac/connect-version.txt","windows/connect.ps1","windows/connect-version.txt"]:
    p=os.path.join(base,rel)
    if not os.path.isfile(p):
        print(rel, "MISSING"); continue
    t=open(p,encoding="utf-8",errors="replace").read()
    m=re.search(r"ConnectVersion\s*=\s*'([^']+)'", t) or re.search(r"CONNECT_VERSION='([^']+)'", t)
    head=t[:120].replace("\n"," ")
    print(f"{rel}: embedded={m.group(1) if m else '-'} size={len(t)} cr={t.count(chr(13))}")
# show if heal/mountpoint-safe is in server golden on sepidz
for p in ["/usr/local/bin/claude-self-heal","/usr/local/bin/claude-mount","/usr/local/bin/laptop-exec"]:
    t=open(p,encoding="utf-8",errors="replace").read()
    print(os.path.basename(p),
          "missing_bins="+str("_heal_missing_user_bins" in t),
          "in_proc="+str("_in_proc_mounts" in t or "Prefer /proc/mounts" in t or "Never use mountpoint" in t))
'@
[IO.File]::WriteAllText("$env:TEMP\vd.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\vd.py" 'sepidz@192.168.250.70:/tmp/vd.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/vd.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\vd.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\vd.sh" 'sepidz@192.168.250.70:/tmp/vd.sh'
ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 'bash /tmp/vd.sh'

Write-Host 'SMART detail:'
$sout="$env:TEMP\vs.txt"
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','smart@192.168.210.240','cat /usr/local/share/claude-client/connect-version.txt; grep -E "ConnectVersion|CONNECT_VERSION" /usr/local/share/claude-client/connect.ps1 /usr/local/share/claude-client/mac/connect.sh 2>/dev/null | head') -NoNewWindow -PassThru -RedirectStandardOutput $sout -RedirectStandardError "$sout.err"
[void]$p.WaitForExit(15000)
Get-Content $sout -Raw
