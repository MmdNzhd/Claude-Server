$sh=Get-Content 'scripts/client/git-mode.sh'
367..480 | ForEach-Object { '{0,4}|{1}' -f $_, $sh[$_-1] }
Write-Output '==== connect.sh tunnel wait loop ===='
Select-String -Path 'scripts/client/mac/connect.sh' -Pattern 'tunnel_up|sync_session|connection dropped|Test-Tunnel' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Output '==== duplicate diagnostic? ===='
Get-Item 'scripts/client/connect-diagnostic.ps1','scripts/client/windows/connect-diagnostic.ps1' -ErrorAction SilentlyContinue |
  ForEach-Object { '{0} len={1}' -f $_.FullName, $_.Length }
# bat version
Select-String -Path 'scripts/client/windows/connect.bat' -Pattern '20260717|ConnectVersion|CONNECT_VERSION' |
  ForEach-Object { $_.Line.Trim() }
