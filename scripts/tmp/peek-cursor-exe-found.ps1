Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\connect-diagnostic.ps1','D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1','D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1' -Pattern 'CursorExeFound' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
