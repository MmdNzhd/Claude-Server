$ErrorActionPreference = 'Stop'
$ver = '20260720.14'
foreach ($rel in @('scripts/client/windows/connect-version.txt','scripts/client/mac/connect-version.txt')) {
  $p = Join-Path (Get-Location) $rel
  $raw = if (Test-Path $p) { (Get-Content -LiteralPath $p -Raw).Trim() } else { '' }
  Write-Host "BEFORE $rel=[$raw]"
  [System.IO.File]::WriteAllText($p, $ver + "`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "AFTER  $rel=[$((Get-Content -LiteralPath $p -Raw).Trim())]"
}
# Ensure ps1/sh versions
$ps1 = Get-Content scripts/client/windows/connect.ps1 -Raw
if ($ps1 -notmatch "ConnectVersion = '20260720\.14'") {
  Write-Host 'WARN: connect.ps1 version not .14'
} else { Write-Host 'connect.ps1 version OK' }
$sh = Get-Content scripts/client/mac/connect.sh -Raw
if ($sh -notmatch "CONNECT_VERSION='20260720\.14'") {
  Write-Host 'WARN: connect.sh version not .14'
} else { Write-Host 'connect.sh version OK' }

# Check PERF in source mount
$cm = Get-Content scripts/server/claude-mount.sh -Raw
Write-Host ("source PERF_HIDE_MS=" + [int]($cm -match 'PERF_HIDE_MS'))
Write-Host ("source BANNER_OK=" + [int]($cm -match 'CLAUDE_TUNNEL_BANNER_OK'))

# Re-publish smart if share missing Request
Write-Host '--- publish SmartOnly SkipVersionBump ---'
& powershell -NoProfile -File publish/publish.ps1 -SmartOnly -SkipVersionBump
Write-Host ("publish exit=" + $LASTEXITCODE)
