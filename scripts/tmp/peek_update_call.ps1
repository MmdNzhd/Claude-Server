$root='D:\Smart\Claude-Code-Server'
Select-String -Path "$root\scripts\client\windows\connect.ps1" -Pattern 'connect-update|Update' |
  Select-Object -First 25 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '--- mac ---'
Select-String -Path "$root\scripts\client\mac\connect.sh","$root\scripts\client\mac\connect-update.sh" -Pattern 'connect-update|claude-server|SERVER' |
  Select-Object -First 30 | ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }
Get-Content "$root\scripts\client\windows\connect-update.ps1" -TotalCount 120
