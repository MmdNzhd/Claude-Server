$ErrorActionPreference = 'Continue'
$root = (Get-Location).Path
$audit = Join-Path $root 'scripts\client\tests\deep-audit-log.ps1'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$today = Join-Path $logDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$yest = Join-Path $logDir ('connect-{0}.log' -f (Get-Date).AddDays(-1).ToString('yyyyMMdd'))
$target = $null
if (Test-Path -LiteralPath $today) { $target = $today }
elseif (Test-Path -LiteralPath $yest) { $target = $yest }
Write-Host "deep-audit script: $audit"
Write-Host "deep-audit target: $target"
if (-not (Test-Path -LiteralPath $audit)) { Write-Host 'SKIP: deep-audit-log.ps1 missing'; exit 0 }
if (-not $target) { Write-Host 'SKIP: no connect day log'; exit 0 }
& $audit -LogPath $target
if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
