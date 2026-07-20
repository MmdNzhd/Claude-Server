Write-Output '=== connect.bat full update+relaunch ==='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.bat' | Select-Object -First 45 | ForEach-Object { $_ }
Write-Output '=== connect.ps1 dotsource once ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'dot-source|\. \$|git-mode|connect-ui' | Select-Object -First 15 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== mac early/late update ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh' -Pattern 'connect-update|need_relaunch|exec |re-run' | Select-Object -First 20 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
