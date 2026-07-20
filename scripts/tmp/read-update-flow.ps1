Write-Output '=== connect-update.ps1 structure ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' -Pattern 'function |need_relaunch|exit |Copy|scp|manifest|version|running|lock' | Select-Object -First 60 | ForEach-Object { "{0,4}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== connect.bat update hooks ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.bat' -Pattern 'update|relaunch|connect-update' | ForEach-Object { "{0,4}|{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== mid-session update checks? ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1','D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1' -Pattern 'connect-update|Check-Update|UPDATE_|auto.update|every.*min' | Select-Object -First 30 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Output '=== docs publish auto-update ==='
Select-String -Path 'D:\Smart\Claude-Code-Server\docs\client-connect.md' -Pattern 'auto-update|update|relaunch|bundle' | Select-Object -First 25 | ForEach-Object { $_.Line.Trim() }
