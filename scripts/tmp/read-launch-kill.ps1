$f = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
Get-Content $f | Select-Object -Skip 1010 -First 140 | ForEach-Object -Begin { $i=1011 } -Process { "{0,4}|{1}" -f $i, $_; $i++ }
Write-Host '===='
Get-Content $f | Select-Object -Skip 1165 -First 50 | ForEach-Object -Begin { $i=1166 } -Process { "{0,4}|{1}" -f $i, $_; $i++ }
