Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\*.ps1','D:\Smart\Claude-Code-Server\scripts\client\windows\*.ps1','D:\Smart\Claude-Code-Server\scripts\client\tests\*.ps1' -Pattern 'CURSOR_NOT_FOUND' |
  ForEach-Object { "$($_.Path | Split-Path -Leaf):$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '--- test-editor-launch Ensure ---'
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\tests\test-editor-launch.ps1' -Pattern 'Ensure-Editor|Programs\\cursor|editor on path' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
# LaptopUser where set
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern 'script:LaptopUser\s*=' |
  Select-Object -First 10 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
