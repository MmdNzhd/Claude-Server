$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

function SshTimed([string]$Target, [string]$Cmd, [int]$Sec=20) {
  $out = [IO.Path]::GetTempFileName()
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','-o','ControlPath=none',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  if (-not $p.WaitForExit($Sec*1000)) { try{$p.Kill()}catch{}; return "TIMEOUT" }
  return ((Get-Content $out -Raw -EA SilentlyContinue) + '').Trim()
}

$sep = SshTimed 'sepidz@192.168.250.70' "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
$smart = SshTimed 'smart@192.168.210.240' "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
$repo = (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim()
Write-Host "REPO=$repo"
Write-Host "SEPIDZ_LIVE=$sep"
Write-Host "SMART_LIVE=$smart"

# quick bin markers on sepidz
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
# push heal if needed via timed
foreach ($pair in @(
  @("$root\scripts\server\claude-self-heal.sh","/tmp/claude-self-heal.sh"),
  @("$root\scripts\server\laptop-exec.sh","/tmp/laptop-exec.sh"),
  @("$root\scripts\server\claude-mount.sh","/tmp/claude-mount.sh"),
  @("$root\scripts\server\laptop-exec-setup.sh","/tmp/laptop-exec-setup.sh"),
  @("$root\scripts\server\claude-automount.sh","/tmp/claude-automount.sh")
)) {
  & scp -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -q $pair[0] ("sepidz@192.168.250.70:"+$pair[1])
}
$py = @'
import os
for s,d in [("/tmp/claude-self-heal.sh","/usr/local/bin/claude-self-heal"),("/tmp/laptop-exec.sh","/usr/local/bin/laptop-exec"),("/tmp/claude-mount.sh","/usr/local/bin/claude-mount"),("/tmp/laptop-exec-setup.sh","/usr/local/bin/laptop-exec-setup"),("/tmp/claude-automount.sh","/usr/local/bin/claude-automount")]:
  data=open(s,"rb").read().replace(b"\r\n",b"\n").replace(b"\r",b"\n")
  open(d,"wb").write(data); os.chmod(d,0o755)
  t=data.decode("utf-8","replace")
  print(os.path.basename(d), "CR", data.count(b"\r"), "heal" if "_heal_missing" in t else ("proc" if "_in_proc" in t or "Prefer /proc" in t or "Never use mountpoint" in t else "ok"))
print("VER", open("/usr/local/share/claude-client/connect-version.txt").read().strip())
'@
[IO.File]::WriteAllBytes("$env:TEMP\vbins.py", [Text.Encoding]::UTF8.GetBytes($py.Replace("`r`n","`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\vbins.py" 'sepidz@192.168.250.70:/tmp/vbins.py'
$bw = ((@('#!/bin/bash',('PW=$(echo {0} | base64 -d)' -f $pwB64),'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/vbins.py') -join "`n")+"`n")
[IO.File]::WriteAllBytes("$env:TEMP\vbins.sh", [Text.Encoding]::UTF8.GetBytes($bw))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\vbins.sh" 'sepidz@192.168.250.70:/tmp/vbins.sh'
$bout = [IO.Path]::GetTempFileName()
$bp = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','sepidz@192.168.250.70','bash /tmp/vbins.sh') -NoNewWindow -PassThru -RedirectStandardOutput $bout -RedirectStandardError "$bout.err"
[void]$bp.WaitForExit(60000)
Write-Host (Get-Content $bout -Raw -EA SilentlyContinue)
Write-Host 'DONE_VERIFY'
