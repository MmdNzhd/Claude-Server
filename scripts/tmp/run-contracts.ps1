$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root
$script = Join-Path $root 'scripts\tmp\test-tunnel-contracts.ps1'
& $script
exit $LASTEXITCODE
