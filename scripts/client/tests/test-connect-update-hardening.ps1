# test-connect-update-hardening.ps1 - static contracts for update apply hardening
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== connect-update hardening contracts ==="
Write-Host ""

$win = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
$mac = Get-Content (Join-Path $RepoRoot 'scripts\client\mac\connect-update.sh') -Raw
$bat = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.bat') -Raw
$dcb = Get-Content (Join-Path $RepoRoot 'scripts\server\commands\deploy-client-bundle.sh') -Raw
$upd = Get-Content (Join-Path $RepoRoot 'scripts\server\commands\update-server.sh') -Raw
$pub = Get-Content (Join-Path $RepoRoot 'publish\deploy-client-bundles.ps1') -Raw
$macConn = Get-Content (Join-Path $RepoRoot 'scripts\client\mac\connect.sh') -Raw

Assert ($win -match "1 = update failed") 'win exit-code docs include ERROR=1'
Assert ($win -match "IdentityAgent=none") 'win update SSH uses IdentityAgent=none'
Assert ($win -match "IdentitiesOnly=yes") 'win update SSH uses IdentitiesOnly=yes'
Assert ($win -match "function Test-BundleChecksums") 'win verifies checksums after download'
Assert ($win -match "Swap-LiveDir|\.client-update-new") 'win stages then swaps live dirs'
Assert ($win -match "apply_rollback") 'win rolls back on swap failure'
Assert ($win -match "incomplete_files=.*\r?\n\s*exit 1" -or ($win -match 'incomplete_files=' -and $win -match 'exit 1')) 'win incomplete apply exits 1'
# Explicit: ERROR download exits 1
Assert ($win -match "download_failed' 'ERROR'[\s\S]{0,120}exit 1") 'win download_failed exits 1'
Assert ($win -notmatch "download_failed' 'ERROR'[\s\S]{0,120}exit 0") 'win download_failed does not exit 0'
Assert ($win -match "Copy-Tracked|\$failed \+=") 'win tracks copy failures'

Assert ($mac -match "IdentityAgent=none") 'mac update SSH uses IdentityAgent=none'
Assert ($mac -match "_run_timed") 'mac update has process kill timeouts'
Assert ($mac -match "_verify_checksums") 'mac verifies checksums'
Assert ($mac -match "_swap_dir") 'mac stages then swaps'
Assert ($mac -match "download_failed" -and $mac -match "exit 1") 'mac ERROR paths exit 1'

Assert ($bat -match "CLAUDE_CONNECT_UPDATE_DEPTH") 'connect.bat bounds update relaunch'
Assert ($bat -match 'UPDATE_FAIL_RELAUNCH_LIMIT|Update failed repeatedly') 'connect.bat bounds exit=1 update fail relaunch'
Assert ($bat -match '-STA') 'connect.bat uses STA for update progress UI'
Assert ($bat -match 'CLAUDE_CONNECT_UPDATE_UI=1') 'connect.bat enables update progress UI'
Assert ($win -match 'Show-UpdateProgressUi') 'connect-update.ps1 has progress modal'
Assert ($win -match 'Get-SafeFileSha256') 'connect-update.ps1 guards FileHash under StrictMode'
Assert ($bat -match "GEQ 3") 'connect.bat relaunch depth limit is 3'
Assert ($bat -match 'start "" /D "%HERE(_NOTRAIL)?%" powershell(\.exe)? -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot\.ps1"') 'connect.bat async handoff to connect-boot.ps1'
Assert ($bat -notmatch '-WindowStyle Hidden -ExecutionPolicy Bypass -File "%HERE%connect\.ps1"') 'connect.bat does not inline-hidden connect.ps1'
Assert ($bat -match 'exit /b 0') 'connect.bat exits after connect.ps1 handoff'

Assert ($macConn -match "CLAUDE_CONNECT_UPDATE_DEPTH") 'mac connect.sh bounds update relaunch'

Assert ($dcb -match "STAGE_BUNDLE") 'deploy-client-bundle stages before swap'
Assert ($dcb -match "BUNDLE_LIVE") 'deploy-client-bundle tracks live path'
Assert ($dcb -match "checksums\.txt") 'deploy-client-bundle writes checksums.txt'
# Flat share must ship CANON diagnostic/ui — not windows/ STALE-SHADOW wrappers
Assert ($dcb -match 'connect-ui\.ps1\|connect-diagnostic\.ps1\|editor-launch') 'deploy-client-bundle maps connect-diagnostic from CLIENT_DIR canon'
Assert ($dcb -match 'scripts/client/connect-diagnostic\.ps1') 'deploy-client-bundle stages scripts/client/connect-diagnostic.ps1'
Assert ($dcb -match 'STALE-SHADOW REPLACED') 'deploy-client-bundle fail-closed rejects STALE-SHADOW wrappers'
Assert ($dcb -match '_verify_staged_client_bundle') 'deploy-client-bundle runs ship-gate verifier before promote'

Assert ($dcb -match '_stage_repo_from_laptop; then') 'deploy-client-bundle prefers laptop staging before /opt'
Assert ($dcb -match '_resolve_repo_fallback') 'deploy-client-bundle uses fallback only after laptop stage'
Assert ($dcb -notmatch '(?m)^_resolve_repo \|\| _stage_repo_from_laptop') 'deploy-client-bundle does not prefer /opt over laptop'
Assert ($dcb -match 'BUNDLE_SOURCE_KIND') 'deploy-client-bundle records laptop vs server-fallback source'
Assert ($dcb -notmatch '(?m)^rm -rf "\$BUNDLE_ROOT"$') 'deploy-client-bundle does not rm -rf live root'

Assert ($upd -match "VERIFY_OK") 'update-server tracks verify result'
Assert ($upd -match "Update finished with verify failures") 'update-server fails on verify'

Assert ($pub -match "UTF8Encoding\]::new\(\`$false\)" -or $pub -match 'UTF8Encoding]::new\(\$false\)') 'publish manifest written without BOM'
Assert ($pub -match "checksums\.txt") 'publish deploy writes checksums.txt'
Assert ($pub -notmatch "Set-Content -Path \(Join-Path \$StageDir 'manifest\.txt'\) -Encoding UTF8") 'publish no longer Set-Content UTF8 BOM for manifest'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
