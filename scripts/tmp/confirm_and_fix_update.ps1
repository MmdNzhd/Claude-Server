$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function SshT([string]$Target, [string]$Cmd, [int]$Sec=25) {
  $o = [IO.Path]::GetTempFileName()
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
  if (-not $p.WaitForExit($Sec*1000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}

Write-Host '=== SEPIDZ BUNDLE ==='
Write-Host (SshT 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt')
# write small py remotely
$py = @'
import re
t=open("/usr/local/share/claude-client/connect.ps1",encoding="utf-8",errors="replace").read()
print("embedded", re.findall(r"ConnectVersion\s*=\s*'([^']+)'", t)[:1])
print("ips", sorted(set(re.findall(r"192\.168\.\d+\.\d+", t))))
'@
[IO.File]::WriteAllBytes("$env:TEMP\chk.py", [Text.Encoding]::UTF8.GetBytes($py.Replace("`r`n","`n")))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\chk.py" 'sepidz@192.168.250.70:/tmp/chk.py'
Write-Host (SshT 'sepidz@192.168.250.70' 'python3 /tmp/chk.py')

Write-Host '=== SMART BUNDLE ==='
Write-Host (SshT 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt')
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\chk.py" 'smart@192.168.210.240:/tmp/chk.py'
Write-Host (SshT 'smart@192.168.210.240' 'python3 /tmp/chk.py')

Write-Host '=== LAPTOP SSH CONFIG claude-server ==='
$cfg = Join-Path $env:USERPROFILE '.ssh\config'
if (Test-Path $cfg) {
  $lines = Get-Content $cfg
  $in=$false
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '^\s*Host\s+claude-server\s*$') { $in=$true; Write-Host $lines[$i]; continue }
    if ($in) {
      if ($lines[$i] -match '^\s*Host\s+') { break }
      Write-Host $lines[$i]
    }
  }
} else { Write-Host 'no ~/.ssh/config' }

Write-Host '=== BAD FOLDER (user tested) ==='
$bad = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
$raw = Get-Content (Join-Path $bad 'connect.ps1') -Raw
Write-Host ("ver={0} ip={1}" -f (Get-Content (Join-Path $bad 'connect-version.txt') -Raw).Trim(), ([regex]::Match($raw,'192\.168\.\d+\.\d+').Value))

Write-Host '=== GOOD FOLDER (latest publish) ==='
$good = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260718\claude-code\windows'
$raw2 = Get-Content (Join-Path $good 'connect.ps1') -Raw
Write-Host ("ver={0} ip={1}" -f (Get-Content (Join-Path $good 'connect-version.txt') -Raw).Trim(), ([regex]::Match($raw2,'192\.168\.\d+\.\d+').Value))
