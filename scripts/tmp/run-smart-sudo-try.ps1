$ErrorActionPreference='Continue'
# kill hung previous
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'finish-smart-sure' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue; Write-Output "killed $($_.ProcessId)" }
$env:PYTHONUNBUFFERED='1'
python -u 'D:\Smart\Claude-Code-Server\scripts\tmp\smart-sudo-try-timeout.py'
exit $LASTEXITCODE
