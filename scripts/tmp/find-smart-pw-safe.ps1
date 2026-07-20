$ErrorActionPreference='SilentlyContinue'
# Find smart-deploy files WITHOUT printing secrets — only lengths/presence
$hits = @()
$roots = @(
  'D:\Smart\Claude-Code-Server\publish',
  "$env:USERPROFILE\.config",
  "$env:USERPROFILE\Desktop\claude-publish",
  'D:\Smart'
)
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  Get-ChildItem $r -Recurse -Filter '*smart*deploy*' -ErrorAction SilentlyContinue |
    Select-Object -First 20 | ForEach-Object { $hits += $_.FullName }
  Get-ChildItem $r -Recurse -Filter '*sudo*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'local|secret|pass' } |
    Select-Object -First 20 | ForEach-Object { $hits += $_.FullName }
}
$hits | Select-Object -Unique | ForEach-Object { Write-Output "HIT $_" }
# Env vars presence only
Write-Output ("ENV_SMART_SUDO={0}" -f [bool]$env:SMART_SUDO_PASSWORD)
Write-Output ("ENV_SEPIDZ_SUDO={0}" -f [bool]$env:SEPIDZ_SUDO_PASSWORD)
# Check Windows Credential Manager entries names only
cmdkey /list 2>$null | Select-String -Pattern 'smart|sepidz|192.168.210|sudo' | ForEach-Object { $_.Line.Trim() }
