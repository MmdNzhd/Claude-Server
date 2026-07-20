$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
$py = @'
import json
cm=open("/usr/local/lib/claude-mount").read()
assert "Only remote User settings" in cm
assert "git.repositoryScanMaxDepth" in cm
assert 'want = {"git.enabled"' not in cm  # old workspace-only form
for u in ("farzadb","hosseinm","hosseinb"):
  j=json.load(open(f"/home/{u}/.cursor-server/data/User/settings.json"))
  assert j.get("git.enabled") is False
  assert j.get("git.autoRepositoryDetection") is False
  assert j.get("git.repositoryScanMaxDepth") == 0
  print("OK", u, "remote git disabled")
print("ALL_GIT_GREEN")
'@
[IO.File]::WriteAllText("$env:TEMP\vgf.py", $py)
scp -o BatchMode=yes -q "$env:TEMP\vgf.py" 'sepidz@192.168.250.70:/tmp/vgf.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/vgf.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\vgf.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\vgf.sh" 'sepidz@192.168.250.70:/tmp/vgf.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/vgf.sh'
# repo check
$mount = Get-Content 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' -Raw
if ($mount -notmatch 'Only remote User settings') { throw 'repo mount missing policy' }
Write-Host 'REPO_OK'
