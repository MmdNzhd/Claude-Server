Set-Location 'D:\Smart\Claude-Code-Server'
Select-String -Path scripts\client\git-mode.sh -Pattern 'seq 1 |recover-one|recover_mounts' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(150,$_.Line.Trim().Length)))" }
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'banner_miss_tcp_open' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(150,$_.Line.Trim().Length)))" }
# file sizes / dates
Get-Item scripts\client\git-mode.sh,scripts\client\git-mode.ps1,scripts\client\windows\connect.ps1 | Format-Table Name,Length,LastWriteTime -AutoSize
