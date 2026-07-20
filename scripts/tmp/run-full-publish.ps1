$ErrorActionPreference='Continue'
Write-Host 'Cleaning hung ssh.exe to servers (keep reverse tunnel)...'
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -and
    ($_.CommandLine -match '192\.168\.210\.240|192\.168\.250\.70|smart@|sepidz@') -and
    ($_.CommandLine -notmatch '-R\s+\d+:localhost:22')
  } |
  ForEach-Object {
    Write-Host "  kill hung ssh pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

Write-Host ''
Write-Host '=== PUBLISH -SkipVersionBump (keep 20260717.5) ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File 'publish\publish.ps1' -SkipVersionBump
$code = $LASTEXITCODE
Write-Host "PUBLISH_EXIT=$code"
exit $code
