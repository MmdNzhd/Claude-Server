# test-windows-shadow-canon.ps1 - Stage G: windows/ ui+diagnostic are wrappers or == canon
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Stage G shadow/canon (static) ===' -ForegroundColor Cyan
$client = $script:ClientRoot
$uiShadow = Join-Path $client 'windows\connect-ui.ps1'
$uiCanon = Join-Path $client 'connect-ui.ps1'
$diagShadow = Join-Path $client 'windows\connect-diagnostic.ps1'
$diagCanon = Join-Path $client 'connect-diagnostic.ps1'
Assert (Test-Path $uiCanon) 'canon connect-ui.ps1 exists'
Assert (Test-Path $diagCanon) 'canon connect-diagnostic.ps1 exists'
$ui = Get-Content $uiShadow -Raw
$diag = Get-Content $diagShadow -Raw
$uiIsWrapper = ($ui -match 'STALE-SHADOW REPLACED' -and $ui -match 'connect-ui\.ps1' -and $ui -match 'Split-Path')
$diagIsWrapper = ($diag -match 'STALE-SHADOW REPLACED' -and $diag -match 'connect-diagnostic\.ps1' -and $diag -match 'Split-Path')
$uiHash = (Get-FileHash $uiShadow -Algorithm SHA256).Hash
$uiCanonHash = (Get-FileHash $uiCanon -Algorithm SHA256).Hash
Assert ($uiIsWrapper -or ($uiHash -eq $uiCanonHash)) 'windows/connect-ui.ps1 is wrapper or hash==canon'
Assert ($diagIsWrapper -or ((Get-FileHash $diagShadow -Algorithm SHA256).Hash -eq (Get-FileHash $diagCanon -Algorithm SHA256).Hash)) 'windows/connect-diagnostic.ps1 is wrapper or hash==canon'
Assert ($ui -notmatch 'function Write-ConnectLog') 'shadow ui does not embed full canon body'
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
