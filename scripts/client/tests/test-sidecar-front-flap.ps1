#Requires -Version 5.1
# test-sidecar-front-flap.ps1 - static contracts for sticky 18998 multi-Connect flap fix:
# BootReap must not kill live fronts; watchdog must hold a Job detach; Clear must
# force-remove dead 18998 even when profile windows are open.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== sidecar front-flap contracts (18998 ECONNREFUSED) ==='
Write-Host ''

$side = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\cursor-proxy-sidecar.ps1') -Raw
$el = Get-Content (Join-Path $RepoRoot 'scripts\client\editor-launch.ps1') -Raw

Assert ($side -match 'SIDECAR_BOOT_REAP skip reason=') 'BootReap has preserve-fronts skip path'
Assert ($side -match 'orphan_lease_pid=\{1\} front_up=') 'BootReap skip log includes front_up'
Assert ($side -match 'fronts_up') 'BootReap skip reason fronts_up present'
Assert ($side -match 'windows_open') 'BootReap can skip for windows_open'
Assert ($side -match 'Remove-Item -LiteralPath \$lease') 'BootReap still drops stale lease on skip'

Assert ($side -match 'Detach-CursorProxySidecarJobProcess -Process \$pWd') 'Start-CursorProxySidecarWatchdog detaches Job into watchdog'
Assert ($side -match 'CURSOR_PROXY_CLEAR force reason=18998_down_windows_open') 'Clear force path when 18998 down + windows open'
Assert ($side -match 'CURSOR_PROXY_CLEAR force reason=backend_down') 'Clear force path when backend -L down (never repair to 18998)'
Assert ($side -match 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings') 'Ensure stops fronts when backend down'
Assert ($side -match 'SIDECAR_START front_up backend_down stopping_fronts') 'Start refuses to pin settings without backend'
Assert ($side -match '\$nOpen -gt 0 -and \$frontListening') 'CLEAR_SKIP gated on windows open AND front listening'

Assert ($el -match 'Clear-CursorProxySettingsSidecar') 'editor-launch still routes clear through sidecar helper'
Assert ($el -match 'action=repair_sidecar_only') 'editor-launch still logs repair_sidecar_only for open windows'

# Must-not: BootReap must not unconditionally StopWatchdog on every dead lease
$bootFn = [regex]::Match($side, '(?s)function Invoke-CursorProxySidecarBootReap \{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert $bootFn.Success 'extracted Invoke-CursorProxySidecarBootReap'
if ($bootFn.Success) {
    $body = $bootFn.Value
    Assert ($body -match 'Stop-CursorProxySidecarWatchdog') 'BootReap still can stop orphan watchdog when safe'
    Assert ($body -match 'SIDECAR_BOOT_REAP skip') 'BootReap body contains skip before kill'
    # Prefer the real call site (Get-Command-gated try), not a comment mention.
    $skipIdx = $body.IndexOf('SIDECAR_BOOT_REAP skip')
    $call = [regex]::Match($body, 'Get-Command\s+Stop-CursorProxySidecarWatchdog[\s\S]{0,120}?Stop-CursorProxySidecarWatchdog')
    Assert ($call.Success) 'BootReap has Get-Command-gated StopWatchdog call'
    Assert ($skipIdx -ge 0 -and $call.Success -and $call.Index -gt $skipIdx) 'skip path appears before gated StopWatchdog call'
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
