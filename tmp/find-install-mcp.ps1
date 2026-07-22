Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\commands\install.sh' -Pattern 'cursor-mcp' |
  ForEach-Object { 'L{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Get-Content 'D:\Smart\Claude-Code-Server\scripts\server\commands\install.sh' | Select-Object -Skip 278 -First 25
