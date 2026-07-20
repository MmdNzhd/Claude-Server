Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\tests\*.ps1' -Pattern 'LAUNCH_KILL|Stop-CursorServerProfileTree|needKill|pre_launch_agent' -ErrorAction SilentlyContinue |
  ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line.Trim())" }
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch.ps1' -Pattern 'new.window|Agent home|kill' -ErrorAction SilentlyContinue |
  ForEach-Object { "test:$($_.LineNumber):$($_.Line.Trim())" }
# CONNECT_VERSION
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'ConnectVersion\s*=' | Select-Object -First 3
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh' -Pattern 'CONNECT_VERSION=' | Select-Object -First 3
