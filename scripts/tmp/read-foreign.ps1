Set-Location 'D:\Smart\Claude-Code-Server'
$lines=Get-Content scripts\client\git-mode.ps1
970..1025 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }
Write-Output '==== MAC ===='
$gl=Get-Content scripts\client\git-mode.sh
1531..1570 | ForEach-Object { '{0}|{1}' -f $_, $gl[$_-1] }
