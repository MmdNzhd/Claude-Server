Set-Location 'D:\Smart\Claude-Code-Server'

# Write-ConnectLog body
$lines=Get-Content scripts\client\connect-ui.ps1
427..480 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }

Write-Output '=== security check 5 ==='
Select-String -Path scripts\tmp\test-security-contracts.ps1 -Pattern 'CHECK 5|askpass|echo|ADMIN' -Context 0,3

Write-Output '=== askpass script content creation ==='
$gl=Get-Content scripts\client\git-mode.sh
1400..1425 | ForEach-Object { '{0}|{1}' -f $_, $gl[$_-1] }
