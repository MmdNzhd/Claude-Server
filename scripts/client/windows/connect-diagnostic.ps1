# STALE-SHADOW REPLACED: always load canon from parent scripts/client/connect-diagnostic.ps1
# Repo-dev only. deploy-client-bundle / publish MUST ship the canon body into flat packages —
# never this wrapper (Desktop\Claude-Connect has no scripts/client parent).
$ErrorActionPreference = 'Stop'
$_canon = Join-Path (Split-Path -Parent $PSScriptRoot) 'connect-diagnostic.ps1'
if (-not (Test-Path -LiteralPath $_canon)) {
    throw @"
connect-diagnostic canon missing: $_canon
This windows/ file is a repo-dev shadow. Flat installs (Desktop\Claude-Connect) must contain the full connect-diagnostic.ps1 from scripts/client/. Re-run client update, or copy the canon file into this folder.
"@
}
. $_canon
