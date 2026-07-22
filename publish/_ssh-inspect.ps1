$ErrorActionPreference = 'Continue'
Write-Output '=== ssh config Host lines ==='
$cfg = Join-Path $env:USERPROFILE '.ssh\config'
if (Test-Path $cfg) {
  Select-String -Path $cfg -Pattern 'Host |HostName|User |IdentityFile|250\.70|sepidz' | ForEach-Object { $_.Line }
} else { 'NO_SSH_CONFIG' }
Write-Output '=== keys ==='
Get-ChildItem (Join-Path $env:USERPROFILE '.ssh') -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) $($_.Length)" }
Write-Output '=== tcp 22 ==='
$tn = Test-NetConnection 192.168.250.70 -Port 22 -WarningAction SilentlyContinue
Write-Output "TcpTestSucceeded=$($tn.TcpTestSucceeded)"
Write-Output '=== batch ssh sepidz@IP ==='
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new sepidz@192.168.250.70 'echo OK; hostname; whoami' 2>&1
Write-Output "exit=$LASTEXITCODE"
