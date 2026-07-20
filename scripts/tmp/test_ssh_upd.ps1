$ErrorActionPreference = 'Continue'
Write-Host '=== ssh config hosts for 250.70 ==='
Select-String -Path "$env:USERPROFILE\.ssh\config" -Pattern 'Host |HostName |User ' | ForEach-Object { $_.Line }
Write-Host '=== direct sepidz@IP ==='
$sw = [Diagnostics.Stopwatch]::StartNew()
$out = & ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt" 2>&1
Write-Host "ec=$LASTEXITCODE ms=$($sw.ElapsedMilliseconds) out=$out"
Write-Host '=== alias claude-server-sepidz ==='
$sw.Restart()
$out2 = & ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new claude-server-sepidz "cat /usr/local/share/claude-client/connect-version.txt" 2>&1
Write-Host "ec=$LASTEXITCODE ms=$($sw.ElapsedMilliseconds) out=$out2"
Write-Host '=== alias claude-server ==='
$sw.Restart()
$out3 = & ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new claude-server "cat /usr/local/share/claude-client/connect-version.txt" 2>&1
Write-Host "ec=$LASTEXITCODE ms=$($sw.ElapsedMilliseconds) out=$out3"
