$ErrorActionPreference = 'Continue'
$src = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260720\windows'
$dst = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'

# Kill connect using that folder
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'claude-code-client-20260717\\windows' } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Start-Sleep -Seconds 2

# Sync published .4 into the folder user runs
Get-ChildItem $src -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dst $_.Name) -Force
}
Write-Host "DST_VER=$((Get-Content (Join-Path $dst 'connect-version.txt') -Raw).Trim())"
Write-Host "HAS_MULTI=$((Select-String -Path (Join-Path $dst 'connect-ui.ps1') -Pattern 'MULTI_INSTANCE' -Quiet))"
Write-Host "HAS_FAIL_NEED=$((Select-String -Path (Join-Path $dst 'connect.ps1') -Pattern 'FAIL NEED_ADMIN' -Quiet))"
