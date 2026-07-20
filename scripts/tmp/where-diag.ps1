Select-String -Path 'scripts/client/windows/connect.ps1','publish/publish.ps1' -Pattern 'connect-diagnostic' |
  ForEach-Object { '{0}:{1}: {2}' -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
# mac connect loop around 775
$m=Get-Content 'scripts/client/mac/connect.sh'
760..800 | ForEach-Object { '{0,4}|{1}' -f $_, $m[$_-1] }
Write-Output '---'
820..860 | ForEach-Object { '{0,4}|{1}' -f $_, $m[$_-1] }
