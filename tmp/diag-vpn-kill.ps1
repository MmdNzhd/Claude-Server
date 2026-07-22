$ErrorActionPreference = 'Continue'
$day = Get-Date -Format 'yyyyMMdd'
$p = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-$day.log"
Write-Host "LOCAL_LOG=$p exists=$([bool](Test-Path $p))"
if (Test-Path $p) {
  Write-Host "size=$((Get-Item $p).Length) mtime=$((Get-Item $p).LastWriteTime)"
  $pat = 'LAUNCH_KILL|auth_relaunch_never_kill|TUNNEL_DROP|session start|CURSOR_PROXY|RECOVERY_BEGIN|force_auth'
  Select-String -Path $p -Pattern $pat | Select-Object -Last 60 | ForEach-Object { $_.Line }
}
Write-Host '==== CODE AuthRelaunch ===='
$c = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
for ($i = 1609; $i -le 1675; $i++) { '{0,4}|{1}' -f ($i+1), $c[$i] }
Write-Host '==== CODE recovery force_auth ===='
$c2 = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
for ($i = 869; $i -le 895; $i++) { '{0,4}|{1}' -f ($i+1), $c2[$i] }
for ($i = 1934; $i -le 1970; $i++) { '{0,4}|{1}' -f ($i+1), $c2[$i] }
