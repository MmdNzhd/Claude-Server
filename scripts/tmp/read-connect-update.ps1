Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' -Pattern 'editor-launch|manifest|Copy-Item|files' |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '----'
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1' | Select-Object -First 80
