Select-String -Path scripts/client/mac/connect-update.sh,scripts/client/mac/connect.sh -Pattern 'claude-client|connect-version|auto-update|/usr/local/share' |
  Select-Object -First 30 | ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
