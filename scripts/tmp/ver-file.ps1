Get-ChildItem -Recurse -Filter 'connect-version.txt' | ForEach-Object { Write-Output $_.FullName; Get-Content $_.FullName }
Select-String -Path 'publish/*.ps1','scripts/client/**/*.ps1' -Pattern 'Get-RepoConnectVersion|Invoke-BumpConnectVersion|connect-version' |
  Select-Object -First 30 |
  ForEach-Object { '{0}:{1}: {2}' -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
