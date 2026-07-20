Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' -Pattern 'ACTIVE_MOUNT' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
