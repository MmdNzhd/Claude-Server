$base = Join-Path $env:USERPROFILE "Desktop\Claude-Connect"
$cv = Join-Path $base "connect-version.txt"
$ps1 = Join-Path $base "windows\connect.ps1"
if (Test-Path $cv) { Write-Output "=== Desktop connect-version.txt ==="; Get-Content $cv }
else { Write-Output "MISSING: $cv" }
if (Test-Path $ps1) { Write-Output "=== Desktop connect.ps1 ==="; Select-String -Path $ps1 -Pattern "ConnectVersion" | Select-Object -First 1 }
Write-Output "=== claude-publish folders ==="
Get-ChildItem (Join-Path $env:USERPROFILE "Desktop\claude-publish") -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) | $($_.LastWriteTime)" }
Write-Output "=== Downloads claude/connect ==="
Get-ChildItem (Join-Path $env:USERPROFILE "Downloads") -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude|connect' } | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object { "$($_.Name) | $($_.LastWriteTime)" }
