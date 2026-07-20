Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch-strategies.ps1' | Select-Object -First 80
Write-Host '===='
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\tests\*.ps1' -Pattern 'LAUNCH_KILL|Stop-CursorServerProfileTree|needKill|Force' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber): $($_.Line.Trim())" }
