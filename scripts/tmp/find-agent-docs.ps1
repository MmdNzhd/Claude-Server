Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\CURSOR-AUTH-PILOT.md','D:\Smart\Claude-Code-Server\docs\*.md' -Pattern 'Agent|Chat|unexpected|ToS|concurrent|refresh|Request ID' -ErrorAction SilentlyContinue |
  Select-Object -First 40 |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
