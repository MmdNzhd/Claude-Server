$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
$py = @'
import json, os
KEYS = ("git.enabled", "git.autoRepositoryDetection", "git.detectSubmodules", "git.repositoryScanMaxDepth")
paths = [
 "/home/hosseinm/mounts/sepidz-web/.vscode/settings.json",
 "/home/hosseinm/mounts/sepidz-web/Frontend/.vscode/settings.json",
]
for p in paths:
  if not os.path.isfile(p):
    print(p, "missing"); continue
  data = json.load(open(p, encoding="utf-8"))
  for k in KEYS:
    data.pop(k, None)
  with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2); f.write("\n")
  print(p, "stripped", list(data.keys())[:5])
'@
[IO.File]::WriteAllText("$env:TEMP\strip_u.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\strip_u.py" 'sepidz@192.168.250.70:/tmp/strip_u.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' -u hosseinm python3 /tmp/strip_u.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\su.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\su.sh" 'sepidz@192.168.250.70:/tmp/su.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/su.sh'
