# STALE-SHADOW REPLACED: always load canon from parent scripts/client/connect-diagnostic.ps1
$ErrorActionPreference = 'Stop'
$_canon = Join-Path (Split-Path -Parent $PSScriptRoot) 'connect-diagnostic.ps1'
if (-not (Test-Path -LiteralPath $_canon)) {
    throw "connect-diagnostic canon missing: $_canon"
}
. $_canon
