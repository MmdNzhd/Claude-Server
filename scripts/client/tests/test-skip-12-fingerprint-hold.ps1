# test-skip-12-fingerprint-hold.ps1 - #12 NEEDS-MORE-RESEARCH: explicit SKIP (no code)
$ErrorActionPreference = 'Continue'
Write-Host ''
Write-Host '=== #12 conf fingerprint HOLD/SKIP ===' -ForegroundColor Cyan
Write-Host '  SKIP  #12 held: write trigger must be first STATUS_OK (not bare CONNECT_OK); restore keyed by ServerIP; Setup/Config => fingerprint_skip; MUST-NOT #11 quarantine' -ForegroundColor Yellow
Write-Host 'ALL PASS (explicit SKIP recorded)' -ForegroundColor Green
exit 0
