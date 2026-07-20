Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\tmp\test-pipeline-out.txt' -Pattern 'FAIL|failed' |
  ForEach-Object { $_.Line }
