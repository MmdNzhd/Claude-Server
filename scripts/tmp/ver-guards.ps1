Select-String -Path 'scripts/client/windows/connect.bat','scripts/client/mac/connect.sh','publish/publish.ps1' -Pattern '20260717|EXPECT_VER|ConnectVersion' |
  ForEach-Object { '{0}:{1}: {2}' -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
