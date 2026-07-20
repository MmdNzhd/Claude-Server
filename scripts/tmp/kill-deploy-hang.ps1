Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'do-deploys|deploy-client-bundles' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue; "killed ps $($_.ProcessId)" }
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match '192\.168\.(210\.240|250\.70)' -and $_.CommandLine -notmatch '-R\s+\d+:localhost:22' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue; "killed ssh $($_.ProcessId)" }
# Show how password install works in deploy script
Select-String -Path 'publish\deploy-client-bundles.ps1' -Pattern 'SudoPassword|sudo -S|pwCmd|paramiko|ExpectedVersion' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Output '--- py ---'
python -c "import paramiko; print('paramiko', paramiko.__version__)" 2>&1
py -3 -c "import paramiko; print('paramiko', paramiko.__version__)" 2>&1
