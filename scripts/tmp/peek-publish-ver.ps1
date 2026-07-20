Select-String -Path 'D:\Smart\Claude-Code-Server\publish\publish.ps1' -Pattern 'connect-version|ConnectVersion|Version|202607' |
  Select-Object -First 40 |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
