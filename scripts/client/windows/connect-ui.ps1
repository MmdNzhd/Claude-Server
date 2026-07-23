# STALE-SHADOW REPLACED: always load canon from parent scripts/client/connect-ui.ps1
# Repo-dev windows/ sibling must not diverge from publish Src (Stage G).
$ErrorActionPreference = 'Stop'
$_canon = Join-Path (Split-Path -Parent $PSScriptRoot) 'connect-ui.ps1'
if (-not (Test-Path -LiteralPath $_canon)) {
    throw "connect-ui canon missing: $_canon"
}
. $_canon
