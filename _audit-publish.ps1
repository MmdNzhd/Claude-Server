$pub = Join-Path $env:USERPROFILE "Desktop\claude-publish\claude-code-client"
foreach ($p in @(
  (Join-Path $pub "windows\connect-version.txt"),
  (Join-Path $pub "mac\connect-version.txt"),
  (Join-Path $pub "windows\connect.ps1")
)) {
  if (Test-Path $p) {
    Write-Output "=== $p ==="
    if ($p -like '*connect.ps1') { Select-String -Path $p -Pattern 'ConnectVersion' | Select-Object -First 1 }
    else { Get-Content $p }
  } else { Write-Output "MISSING $p" }
}
