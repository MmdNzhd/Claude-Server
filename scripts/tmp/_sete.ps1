Select-String -Path scripts/client/mac/connect.sh,scripts/client/git-mode.sh -Pattern 'set -[a-z]*e|source.*git-mode|\. .*git-mode' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim())" }
# connect-update failure modes
Get-Content scripts/client/mac/connect-update.sh | Select-Object -First 160
