$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"
$expected = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()

$sepVer = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$smartOut = "$env:TEMP\smv2.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','smart@192.168.210.240',"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $smartOut -RedirectStandardError "$smartOut.err"
[void]$p2.WaitForExit(12000)
$smartVer = if (Test-Path $smartOut) { (Get-Content $smartOut -Raw).Trim() } else { '?' }
Write-Host "SEPIDZ_LIVE=$sepVer expected=$expected"
Write-Host "SMART_LIVE=$smartVer (must remain 20260717.22)"
if ($sepVer -ne $expected) { throw "sepidz mismatch" }
if ($smartVer -ne '20260717.22') { Write-Host "WARN smart changed to $smartVer" }

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh","/tmp/claude-self-heal.sh"),
  @("$root\scripts\server\laptop-exec-setup.sh","/tmp/laptop-exec-setup.sh"),
  @("$root\scripts\server\claude-automount.sh","/tmp/claude-automount.sh"),
  @("$root\scripts\server\laptop-exec.sh","/tmp/laptop-exec.sh"),
  @("$root\scripts\server\claude-mount.sh","/tmp/claude-mount.sh")
)) { scp -o BatchMode=yes -q $pair[0] ("sepidz@192.168.250.70:"+$pair[1]) }

$pyLines = @(
'import os,pwd',
'm={',
'"/tmp/claude-self-heal.sh":["/usr/local/bin/claude-self-heal"],',
'"/tmp/laptop-exec-setup.sh":["/usr/local/bin/laptop-exec-setup"],',
'"/tmp/claude-automount.sh":["/usr/local/bin/claude-automount"],',
'"/tmp/laptop-exec.sh":["/usr/local/bin/laptop-exec","/usr/local/lib/claude-server/laptop-exec.sh"],',
'"/tmp/claude-mount.sh":["/usr/local/bin/claude-mount","/usr/local/lib/claude-mount"],',
'}',
'for s,ds in m.items():',
'    data=open(s,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")',
'    for d in ds:',
'        os.makedirs(os.path.dirname(d),exist_ok=True)',
'        open(d,"wb").write(data); os.chmod(d,0o755); print("ok",d)',
'for ent in pwd.getpwall():',
'    if ent.pw_uid < 1000: continue',
'    home=ent.pw_dir',
'    if not os.path.isdir(home): continue',
'    if not (os.path.isdir(home+"/.cursor-server") or os.path.isfile(home+"/.claude-connect.conf")): continue',
'    os.makedirs(home+"/.local/bin", exist_ok=True)',
'    for name in ("claude-self-heal","laptop-exec-setup","claude-automount","laptop-exec","claude-mount"):',
'        sysp="/usr/local/bin/"+name',
'        if not os.path.isfile(sysp): continue',
'        dst=home+"/.local/bin/"+name',
'        open(dst,"wb").write(open(sysp,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b""))',
'        os.chmod(dst,0o755)',
'        try: os.chown(dst, ent.pw_uid, ent.pw_gid)',
'        except OSError: pass',
'print("BINS_OK")'
)
[IO.File]::WriteAllBytes("$env:TEMP\bins.py", [Text.Encoding]::UTF8.GetBytes((($pyLines -join "`n")+"`n")))
scp -o BatchMode=yes -q "$env:TEMP\bins.py" 'sepidz@192.168.250.70:/tmp/bins.py'
$bw = ((@('#!/bin/bash',('PW=$(echo {0} | base64 -d)' -f $pwB64),'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/bins.py') -join "`n")+"`n")
[IO.File]::WriteAllBytes("$env:TEMP\bins.sh", [Text.Encoding]::UTF8.GetBytes($bw))
scp -o BatchMode=yes -q "$env:TEMP\bins.sh" 'sepidz@192.168.250.70:/tmp/bins.sh'
ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 'bash /tmp/bins.sh'
Write-Host 'SEPIDZ_DEPLOY_COMPLETE_NO_PROMPT'
