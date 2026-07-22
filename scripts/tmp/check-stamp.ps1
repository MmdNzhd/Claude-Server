Set-Location D:\Smart\Claude-Code-Server
Get-Content scripts/client/connect-ui.ps1 | Select-Object -Skip 800 -First 95 | ForEach-Object -Begin {$i=801} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }
