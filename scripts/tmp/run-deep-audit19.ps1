$ErrorActionPreference = 'Continue'
$root = (Get-Location).Path
$audit = Join-Path $root 'scripts\client\tests\deep-audit-log.ps1'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
Write-Host "deep-audit target: $log len=$((Get-Item -LiteralPath $log).Length)"
& $audit -LogPath $log
